import Foundation

#if canImport(LibtorrentAppleBinary)
import LibtorrentAppleBinary
#elseif canImport(LibtorrentAppleBridge)
import LibtorrentAppleBridge
#endif

private struct TrackedTorrent: Sendable, Hashable, Codable {
    var source: TorrentSource
    var name: String
    var downloadDirectory: URL
    var state: TorrentState
    var metrics: TorrentMetrics
    var addedAt: Date
    var updatedAt: Date
}

private struct ThroughputOptimizerRuntimeState: Sendable {
    var consecutiveLowSpeedWindows = 0
    var consecutiveZeroSpeedWindows = 0
    var stableRecoveryWindows = 0
    var isBoosted = false
    var lastActionAt: Date?
}

private struct RehydrationSeed: Sendable {
    let tracked: TrackedTorrent
    let nativeResumeData: Data?
}

public actor TorrentSession {
    public private(set) var configuration: SessionConfiguration
    public private(set) var isRunning = false

    private static let statusReadFailureAlertInterval = 20

    private var nativeSession: BridgeSessionHandle?
    private var alertPollTask: Task<Void, Never>?
    private var deferredApplyTask: Task<Void, Never>?
    private var deferredConfiguration: SessionConfiguration?
    private var throughputOptimizerTask: Task<Void, Never>?
    private var throughputOptimizerPolicy: SessionThroughputOptimizerPolicy?
    private var throughputOptimizerBaseConfiguration: SessionConfiguration?
    private var throughputOptimizerState = ThroughputOptimizerRuntimeState()
    private var throughputOptimizerInternalApply = false
    private var torrents: [TorrentID: TrackedTorrent] = [:]
    private var statusReadFailureCounts: [TorrentID: Int] = [:]
    private let alertStreamStorage: AsyncStream<TorrentAlert>
    private let alertContinuation: AsyncStream<TorrentAlert>.Continuation

    public init(configuration: SessionConfiguration = .default) {
        self.configuration = configuration

        var continuation: AsyncStream<TorrentAlert>.Continuation?
        let stream = AsyncStream<TorrentAlert> { createdContinuation in
            continuation = createdContinuation
        }

        self.alertStreamStorage = stream
        self.alertContinuation = continuation!
    }

    public func alerts() -> AsyncStream<TorrentAlert> {
        alertStreamStorage
    }

    public func handle(for id: TorrentID) -> TorrentHandle? {
        guard torrents[id] != nil else {
            return nil
        }

        return TorrentHandle(session: self, id: id)
    }

    public func handles() -> [TorrentHandle] {
        torrents
            .sorted { lhs, rhs in
                lhs.value.addedAt < rhs.value.addedAt
            }
            .map { TorrentHandle(session: self, id: $0.key) }
    }

    public func downloadController(for id: TorrentID) -> TorrentDownloadController? {
        guard torrents[id] != nil else {
            return nil
        }

        return TorrentDownloadController(session: self, torrentID: id)
    }

    public func statsUpdates(
        pollInterval: TimeInterval = 1,
        emitInitialValue: Bool = true,
        onlyChanges: Bool = true
    ) -> AsyncStream<TorrentDownloaderStats> {
        AsyncStream { continuation in
            let task = Task {
                var lastStats: TorrentDownloaderStats?

                if emitInitialValue {
                    let initialStats = self.totalStats()
                    continuation.yield(initialStats)
                    lastStats = initialStats
                }

                while !Task.isCancelled {
                    try? await AsyncTiming.sleep(seconds: pollInterval)
                    if Task.isCancelled {
                        break
                    }

                    let nextStats = self.totalStats()
                    if !onlyChanges || nextStats != lastStats {
                        continuation.yield(nextStats)
                        lastStats = nextStats
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func pieceUpdates(
        for id: TorrentID,
        pollInterval: TimeInterval = 1,
        emitInitialValue: Bool = true,
        onlyChanges: Bool = true
    ) -> AsyncThrowingStream<TorrentPieceSnapshot, Error> {
        guard torrents[id] != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LibtorrentAppleError.torrentNotFound(id))
            }
        }

        let controller = TorrentDownloadController(session: self, torrentID: id)
        return controller.updates(
            pollInterval: pollInterval,
            emitInitialValue: emitInitialValue,
            onlyChanges: onlyChanges
        )
    }

    public func start() throws {
        try BridgeRuntime.requireAvailable()

        guard !isRunning else {
            return
        }

        let session: BridgeSessionHandle
        do {
            session = try BridgeRuntime.createSession(configuration: configuration)
        } catch {
            throw translatedConfigurationError(error)
        }

        do {
            nativeSession = session
            try rehydrateTrackedTorrents()
            isRunning = true
            startNativeAlertPolling()
            emitAlert(.sessionStarted, message: "Torrent session started.")
        } catch {
            stopNativeAlertPolling()
            BridgeRuntime.destroySession(session)
            nativeSession = nil
            throw error
        }
    }

    public func applyConfiguration(_ configuration: SessionConfiguration) throws {
        if !isRunning {
            self.configuration = configuration
            return
        }

        guard configuration.downloadDirectory == self.configuration.downloadDirectory else {
            throw LibtorrentAppleError.configurationInvalid(
                "runtime apply does not support changing downloadDirectory; recreate the session instead"
            )
        }

        let session = try requireRunningSession()
        do {
            try BridgeRuntime.applyConfiguration(session: session, configuration: configuration)
            self.configuration = configuration
            if throughputOptimizerPolicy != nil,
               !throughputOptimizerInternalApply,
               !throughputOptimizerState.isBoosted
            {
                throughputOptimizerBaseConfiguration = configuration
            }
            emitAlert(.nativeEvent, nativeEventName: "session_configuration_applied", message: "Applied session configuration.")
        } catch {
            throw translatedConfigurationError(error)
        }
    }

    public func applyProfile(_ profile: SessionProfile) throws {
        try applyConfiguration(configuration.applyingProfile(profile))
    }

    public func scheduleConfigurationApply(
        _ configuration: SessionConfiguration,
        debounceInterval: TimeInterval = 0.2
    ) {
        deferredConfiguration = configuration
        deferredApplyTask?.cancel()

        deferredApplyTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await AsyncTiming.sleep(seconds: debounceInterval)
            } catch {
                return
            }

            await self.flushDeferredConfigurationApply()
        }
    }

    @discardableResult
    public func flushDeferredConfigurationApply() async -> Bool {
        deferredApplyTask = nil
        guard let pending = deferredConfiguration else {
            return false
        }
        deferredConfiguration = nil

        do {
            try applyConfiguration(pending)
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_configuration_applied_deferred",
                message: "Applied deferred session configuration."
            )
            return true
        } catch {
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_configuration_apply_deferred_failed",
                message: "Deferred session configuration apply failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    public func setPeerFilters(
        blockedCIDRs: [String],
        allowedCIDRs: [String] = []
    ) throws {
        var updated = configuration
        updated.peerBlockedCIDRs = blockedCIDRs
        updated.peerAllowedCIDRs = allowedCIDRs
        try applyConfiguration(updated)
    }

    public func clearPeerFilters() throws {
        try setPeerFilters(blockedCIDRs: [], allowedCIDRs: [])
    }

    public func setTransportBehavior(_ behavior: SessionTransportBehavior) throws {
        try applyConfiguration(configuration.applyingTransportBehavior(behavior))
    }

    public func scheduleTransportBehaviorApply(
        _ behavior: SessionTransportBehavior,
        debounceInterval: TimeInterval = 0.2
    ) {
        scheduleConfigurationApply(
            configuration.applyingTransportBehavior(behavior),
            debounceInterval: debounceInterval
        )
    }

    public func startThroughputOptimizer(
        policy: SessionThroughputOptimizerPolicy = .default
    ) {
        throughputOptimizerPolicy = policy
        throughputOptimizerBaseConfiguration = configuration
        throughputOptimizerState = ThroughputOptimizerRuntimeState()
        startThroughputOptimizerTaskIfNeeded()
        emitAlert(
            .nativeEvent,
            nativeEventName: "session_throughput_optimizer_started",
            message: "Started throughput optimizer."
        )
    }

    public func stopThroughputOptimizer(restoreBaseline: Bool = true) {
        throughputOptimizerTask?.cancel()
        throughputOptimizerTask = nil
        let shouldRestore = restoreBaseline && throughputOptimizerState.isBoosted
        let baseline = throughputOptimizerBaseConfiguration

        throughputOptimizerPolicy = nil
        throughputOptimizerState = ThroughputOptimizerRuntimeState()
        throughputOptimizerBaseConfiguration = nil

        if shouldRestore,
           let baseline
        {
            do {
                throughputOptimizerInternalApply = true
                try applyConfiguration(baseline)
            } catch {
                emitAlert(
                    .nativeEvent,
                    nativeEventName: "session_throughput_optimizer_restore_failed",
                    message: "Throughput optimizer restore failed: \(error.localizedDescription)"
                )
            }
            throughputOptimizerInternalApply = false
        }

        emitAlert(
            .nativeEvent,
            nativeEventName: "session_throughput_optimizer_stopped",
            message: "Stopped throughput optimizer."
        )
    }

    public func isThroughputOptimizerEnabled() -> Bool {
        throughputOptimizerPolicy != nil
    }

    public func stop() {
        guard isRunning else {
            return
        }

        stopThroughputOptimizer(restoreBaseline: false)
        deferredApplyTask?.cancel()
        deferredApplyTask = nil
        deferredConfiguration = nil
        stopNativeAlertPolling()
        BridgeRuntime.destroySession(nativeSession)
        nativeSession = nil
        statusReadFailureCounts = [:]
        isRunning = false
        emitAlert(.sessionStopped, message: "Torrent session stopped.")
    }

    @discardableResult
    public func addTorrent(from source: TorrentSource, name: String) throws -> TorrentStatus {
        try addTorrent(from: source, options: AddTorrentOptions(displayName: name))
    }

    @discardableResult
    public func addTorrent(from source: TorrentSource, options: AddTorrentOptions = .default) throws -> TorrentStatus {
        let session = try requireRunningSession()
        try validate(source)

        let resolvedName = resolvedName(for: source, explicitName: options.displayName)
        let downloadDirectory = try ensureDownloadDirectory(options.downloadDirectory)
        let id = try addNativeTorrent(session: session, source: source, downloadDirectory: downloadDirectory)
        let timestamp = Date()

        torrents[id] = TrackedTorrent(
            source: source,
            name: resolvedName,
            downloadDirectory: downloadDirectory,
            state: .running,
            metrics: .empty,
            addedAt: timestamp,
            updatedAt: timestamp
        )

        applyTrackerPresetIfNeeded(session: session, torrentID: id)

        let status = try torrentStatus(for: id)
        emitAlert(.torrentAdded, torrentID: status.id, message: "Added torrent \(status.name).")
        return status
    }

    public func addTorrentHandle(from source: TorrentSource, options: AddTorrentOptions = .default) throws -> TorrentHandle {
        let status = try addTorrent(from: source, options: options)
        return TorrentHandle(session: self, id: status.id)
    }

    @discardableResult
    public func addTorrent(fromNativeResumeData data: Data, options: AddTorrentOptions = .default) throws -> TorrentStatus {
        let session = try requireRunningSession()
        guard !data.isEmpty else {
            throw LibtorrentAppleError.invalidTorrentData("Native resume data was empty.")
        }

        let downloadDirectory = try ensureDownloadDirectory(options.downloadDirectory)
        let id = try BridgeRuntime.addResumeData(
            session: session,
            resumeData: data,
            downloadPath: try ensureDownloadPath(downloadDirectory: downloadDirectory)
        )
        let timestamp = Date()
        let source = TorrentSource.magnetLink(
            URL(string: "magnet:?xt=urn:btih:\(id.rawValue)")!,
            displayName: options.displayName
        )

        torrents[id] = TrackedTorrent(
            source: source,
            name: options.displayName ?? "Restored Torrent",
            downloadDirectory: downloadDirectory,
            state: .running,
            metrics: .empty,
            addedAt: timestamp,
            updatedAt: timestamp
        )

        let status = try torrentStatus(for: id)
        emitAlert(.resumeDataRestored, torrentID: id, message: "Added torrent from native resume data.")
        return status
    }

    public func addTorrentHandle(fromNativeResumeData data: Data, options: AddTorrentOptions = .default) throws -> TorrentHandle {
        let status = try addTorrent(fromNativeResumeData: data, options: options)
        return TorrentHandle(session: self, id: status.id)
    }

    public func torrentFiles(for id: TorrentID) throws -> [TorrentFile] {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            return try BridgeRuntime.files(session: session, id: id).map { nativeFile in
                TorrentFile(
                    torrentID: id,
                    index: nativeFile.index,
                    path: nativeFile.path,
                    name: nativeFile.name,
                    sizeBytes: nativeFile.sizeBytes,
                    downloadedBytes: nativeFile.downloadedBytes,
                    priority: nativeFile.priority
                )
            }
        } catch {
            throw translatedMetadataError(error, torrentID: id)
        }
    }

    public func torrentFile(for id: TorrentID, index: Int) throws -> TorrentFile {
        let files = try torrentFiles(for: id)
        guard let file = files.first(where: { $0.index == index }) else {
            throw LibtorrentAppleError.torrentFileNotFound(id, index)
        }

        return file
    }

    public func piecePriorities(for id: TorrentID) throws -> [TorrentDownloadPriority] {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            return try BridgeRuntime.piecePriorities(session: session, id: id)
        } catch {
            throw translatedMetadataError(error, torrentID: id)
        }
    }

    public func torrentTrackers(for id: TorrentID) throws -> [TorrentTracker] {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        return try BridgeRuntime.trackers(session: session, id: id).map { tracker in
            TorrentTracker(
                torrentID: id,
                url: tracker.url,
                tier: tracker.tier,
                failureCount: tracker.failureCount,
                sourceMask: tracker.sourceMask,
                isVerified: tracker.isVerified,
                message: tracker.message
            )
        }
    }

    @discardableResult
    public func replaceTrackers(
        _ trackers: [TorrentTrackerUpdate],
        for id: TorrentID
    ) throws -> [TorrentTracker] {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.replaceTrackers(session: session, id: id, trackers: trackers)
            emitAlert(.torrentTrackersReplaced, torrentID: id, message: "Replaced torrent trackers.")
            return try torrentTrackers(for: id)
        } catch {
            throw translatedTrackerError(error)
        }
    }

    @discardableResult
    public func addTracker(
        _ tracker: TorrentTrackerUpdate,
        for id: TorrentID
    ) throws -> [TorrentTracker] {
        try addTrackers([tracker], for: id)
    }

    @discardableResult
    public func addTrackers(
        _ trackers: [TorrentTrackerUpdate],
        for id: TorrentID,
        forceReannounce: Bool = true
    ) throws -> [TorrentTracker] {
        guard !trackers.isEmpty else {
            return try torrentTrackers(for: id)
        }

        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.addTrackers(
                session: session,
                id: id,
                trackers: trackers,
                forceReannounce: forceReannounce
            )
            emitAlert(.torrentTrackerAdded, torrentID: id, message: "Added \(trackers.count) torrent tracker(s).")
            return try torrentTrackers(for: id)
        } catch {
            throw translatedTrackerError(error)
        }
    }

    public func torrentPeers(for id: TorrentID) throws -> [TorrentPeer] {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        return try BridgeRuntime.peers(session: session, id: id).map { peer in
            TorrentPeer(
                torrentID: id,
                endpoint: peer.endpoint,
                client: peer.client,
                flags: peer.flags,
                sourceMask: peer.sourceMask,
                downloadRateBytesPerSecond: peer.downloadRateBytesPerSecond,
                uploadRateBytesPerSecond: peer.uploadRateBytesPerSecond,
                queueBytes: peer.queueBytes,
                totalDownloadedBytes: peer.totalDownloadedBytes,
                totalUploadedBytes: peer.totalUploadedBytes,
                progress: peer.progress,
                isSeed: peer.isSeed
            )
        }
    }

    public func torrentPieces(for id: TorrentID) throws -> [TorrentPiece] {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            return try BridgeRuntime.pieces(session: session, id: id).map { piece in
                TorrentPiece(
                    torrentID: id,
                    index: piece.index,
                    priority: piece.priority,
                    availability: piece.availability,
                    isDownloaded: piece.isDownloaded
                )
            }
        } catch {
            throw translatedMetadataError(error, torrentID: id)
        }
    }

    @discardableResult
    public func setFilePriority(
        _ priority: TorrentDownloadPriority,
        for id: TorrentID,
        fileIndex: Int
    ) throws -> TorrentFile {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.setFilePriority(session: session, id: id, fileIndex: fileIndex, priority: priority)
            emitAlert(.torrentFilePriorityChanged, torrentID: id, message: "Updated torrent file priority.")
            return try torrentFile(for: id, index: fileIndex)
        } catch {
            throw translatedMetadataError(error, torrentID: id)
        }
    }

    public func setSequentialDownload(_ isEnabled: Bool, for id: TorrentID) throws {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        try BridgeRuntime.setSequentialDownload(session: session, id: id, isEnabled: isEnabled)
        emitAlert(.sequentialDownloadChanged, torrentID: id, message: "Updated sequential download mode.")
    }

    public func forceRecheck(id: TorrentID) throws {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        try BridgeRuntime.forceRecheck(session: session, id: id)
        emitAlert(.torrentRechecked, torrentID: id, message: "Requested torrent recheck.")
    }

    public func forceReannounce(
        id: TorrentID,
        after seconds: Int = 0,
        trackerIndex: Int? = nil,
        ignoreMinimumInterval: Bool = false
    ) throws {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.forceReannounce(
                session: session,
                id: id,
                after: seconds,
                trackerIndex: trackerIndex,
                ignoreMinimumInterval: ignoreMinimumInterval
            )
            emitAlert(.torrentReannounced, torrentID: id, message: "Requested tracker reannounce.")
        } catch {
            throw translatedTrackerError(error)
        }
    }

    @discardableResult
    public func reannounceAllTorrents(
        after seconds: Int = 0,
        ignoreMinimumInterval: Bool = true
    ) throws -> Int {
        let session = try requireRunningSession()
        let torrentIDs = torrents.keys.sorted(by: { $0.rawValue < $1.rawValue })

        var succeeded = 0
        for id in torrentIDs {
            do {
                try BridgeRuntime.forceReannounce(
                    session: session,
                    id: id,
                    after: seconds,
                    trackerIndex: nil,
                    ignoreMinimumInterval: ignoreMinimumInterval
                )
                succeeded += 1
            } catch {
                emitAlert(
                    .torrentTrackerWarning,
                    torrentID: id,
                    message: "Batch reannounce failed: \(error.localizedDescription)"
                )
            }
        }

        emitAlert(
            .nativeEvent,
            nativeEventName: "session_reannounce_all",
            message: "Batch reannounce completed: \(succeeded)/\(torrentIDs.count) torrents."
        )
        return succeeded
    }

    @discardableResult
    public func reopenNetworkSockets(remapPorts: Bool = true) throws -> Bool {
        let session = try requireRunningSession()

        do {
            if try BridgeRuntime.reopenNetworkSockets(session: session, remapPorts: remapPorts) {
                emitAlert(
                    .nativeEvent,
                    nativeEventName: "session_network_sockets_reopened",
                    message: "Reopened network sockets."
                )
                return true
            }
        } catch {
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_network_sockets_reopen_failed",
                message: "Native socket reopen failed: \(error.localizedDescription). Falling back to session rebuild."
            )
        }

        try rebuildNativeSession()
        emitAlert(
            .nativeEvent,
            nativeEventName: "session_network_sockets_rebuilt",
            message: "Native socket reopen unavailable; rebuilt the session to refresh network sockets."
        )
        return false
    }

    @discardableResult
    func recoverNetworkAndReannounce(
        nativeEventName: String,
        triggerDescription: String,
        recovery: () throws -> Bool
    ) throws -> Int {
        let recoveryMessage: String

        do {
            let reopenedNatively = try recovery()
            recoveryMessage = reopenedNatively
                ? "reopened network sockets and triggered batch reannounce."
                : "rebuilt the session and triggered batch reannounce."
        } catch {
            emitAlert(
                .nativeEvent,
                nativeEventName: "\(nativeEventName)_socket_recovery_failed",
                message: "\(triggerDescription); network socket recovery failed: \(error.localizedDescription). Continuing with batch reannounce on the existing session."
            )
            recoveryMessage = "network socket recovery failed; continued with batch reannounce on the existing session."
        }

        let succeeded = try reannounceAllTorrents(after: 0, ignoreMinimumInterval: true)
        emitAlert(
            .nativeEvent,
            nativeEventName: nativeEventName,
            message: "\(triggerDescription); \(recoveryMessage)"
        )
        return succeeded
    }

    @discardableResult
    public func handleNetworkPathChanged() throws -> Int {
        try recoverNetworkAndReannounce(
            nativeEventName: "session_network_path_changed",
            triggerDescription: "Network path changed",
            recovery: { try reopenNetworkSockets(remapPorts: true) }
        )
    }

    @discardableResult
    public func handleSystemWakeupDetected() throws -> Int {
        try recoverNetworkAndReannounce(
            nativeEventName: "session_system_wakeup_detected",
            triggerDescription: "System wakeup detected",
            recovery: { try reopenNetworkSockets(remapPorts: true) }
        )
    }

    @discardableResult
    public func moveStorage(
        for id: TorrentID,
        to directory: URL,
        strategy: TorrentStorageMoveStrategy = .replaceExisting
    ) throws -> URL {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        let resolvedDirectory = try ensureDownloadDirectory(directory)
        do {
            try BridgeRuntime.moveStorage(
                session: session,
                id: id,
                downloadPath: resolvedDirectory.path,
                strategy: strategy
            )
            syncTrackedTorrentDownloadDirectory(id: id, directory: resolvedDirectory)
            emitAlert(.torrentStorageMoved, torrentID: id, message: "Requested torrent storage move.")
            return resolvedDirectory
        } catch {
            throw translatedStorageError(error)
        }
    }

    public func setPiecePriority(
        _ priority: TorrentDownloadPriority,
        for id: TorrentID,
        pieceIndex: Int
    ) throws {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.setPiecePriority(session: session, id: id, pieceIndex: pieceIndex, priority: priority)
            emitAlert(.torrentPiecePriorityChanged, torrentID: id, message: "Updated torrent piece priority.")
        } catch {
            throw translatedPieceControlError(error, torrentID: id)
        }
    }

    public func setPieceDeadline(
        for id: TorrentID,
        pieceIndex: Int,
        milliseconds: Int
    ) throws {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.setPieceDeadline(
                session: session,
                id: id,
                pieceIndex: pieceIndex,
                milliseconds: milliseconds
            )
            emitAlert(.torrentPieceDeadlineChanged, torrentID: id, message: "Updated torrent piece deadline.")
        } catch {
            throw translatedPieceControlError(error, torrentID: id)
        }
    }

    public func resetPieceDeadline(for id: TorrentID, pieceIndex: Int) throws {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.resetPieceDeadline(session: session, id: id, pieceIndex: pieceIndex)
            emitAlert(.torrentPieceDeadlineChanged, torrentID: id, message: "Cleared torrent piece deadline.")
        } catch {
            throw translatedPieceControlError(error, torrentID: id)
        }
    }

    @discardableResult
    public func pauseTorrent(id: TorrentID) throws -> TorrentStatus {
        let session = try requireRunningSession()
        guard var tracked = torrents[id] else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        try BridgeRuntime.pauseTorrent(session: session, id: id)
        tracked.state = .paused
        tracked.updatedAt = Date()
        torrents[id] = tracked
        let status = try torrentStatus(for: id)
        emitAlert(.torrentPaused, torrentID: id, message: "Paused torrent.")
        return status
    }

    @discardableResult
    public func resumeTorrent(id: TorrentID) throws -> TorrentStatus {
        let session = try requireRunningSession()
        guard var tracked = torrents[id] else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        try BridgeRuntime.resumeTorrent(session: session, id: id)
        tracked.state = .running
        tracked.updatedAt = Date()
        torrents[id] = tracked
        let status = try torrentStatus(for: id)
        emitAlert(.torrentResumed, torrentID: id, message: "Resumed torrent.")
        return status
    }

    public func removeTorrent(id: TorrentID, deleteData: Bool = false) throws {
        let session = try requireRunningSession()
        guard let removed = torrents[id] else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        try BridgeRuntime.removeTorrent(session: session, id: id, deleteData: deleteData)
        torrents.removeValue(forKey: id)
        statusReadFailureCounts.removeValue(forKey: id)

        let suffix = deleteData ? " and requested data deletion" : ""
        emitAlert(.torrentRemoved, torrentID: id, message: "Removed torrent \(removed.name)\(suffix).")
    }

    public func torrentStatus(for id: TorrentID) throws -> TorrentStatus {
        let session = try requireRunningSession()
        guard let tracked = torrents[id] else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        let nativeStatus = try BridgeRuntime.status(session: session, id: id)
        let status = materializeStatus(id: id, tracked: tracked, nativeStatus: nativeStatus)
        statusReadFailureCounts.removeValue(forKey: id)
        syncTrackedTorrent(with: status)
        return status
    }

    public func allTorrentStatuses() -> [TorrentStatus] {
        let trackedTorrents = torrents.sorted { lhs, rhs in
            lhs.value.addedAt < rhs.value.addedAt
        }

        guard let session = nativeSession, isRunning else {
            return trackedTorrents.map { materializeCachedStatus(id: $0.key, tracked: $0.value) }
        }

        return trackedTorrents.map { id, tracked in
            do {
                let nativeStatus = try BridgeRuntime.status(session: session, id: id)
                statusReadFailureCounts.removeValue(forKey: id)
                let status = materializeStatus(id: id, tracked: tracked, nativeStatus: nativeStatus)
                syncTrackedTorrent(with: status)
                return status
            } catch {
                let failureCount = (statusReadFailureCounts[id] ?? 0) + 1
                statusReadFailureCounts[id] = failureCount

                if failureCount == 1 || failureCount.isMultiple(of: Self.statusReadFailureAlertInterval) {
                    emitAlert(
                        .nativeEvent,
                        torrentID: id,
                        nativeEventName: "torrent_status_snapshot_failed",
                        message: "Failed to fetch torrent status for \(id.rawValue); using cached snapshot (failure #\(failureCount)): \(error.localizedDescription)"
                    )
                }

                return materializeCachedStatus(id: id, tracked: tracked)
            }
        }
    }

    public func resumeDataSnapshot() -> ResumeDataSnapshot {
        ResumeDataSnapshot(configuration: configuration, torrents: allTorrentStatuses())
    }

    public func totalStats() -> TorrentDownloaderStats {
        TorrentDownloaderStats(statuses: allTorrentStatuses())
    }

    public func sessionDiagnostics() throws -> TorrentSessionDiagnostics {
        let session = try requireRunningSession()
        let nativeStats = try BridgeRuntime.sessionStats(session: session)
        let listenState = try BridgeRuntime.listenState(session: session)
        return TorrentSessionDiagnostics(
            aggregateDownloadRateBytesPerSecond: nativeStats.downloadRateBytesPerSecond,
            aggregateUploadRateBytesPerSecond: nativeStats.uploadRateBytesPerSecond,
            totalConnections: nativeStats.totalConnections,
            totalPeers: nativeStats.totalPeers,
            totalSeeds: nativeStats.totalSeeds,
            isDHTEnabled: nativeStats.isDHTEnabled,
            dhtNodeCount: nativeStats.dhtNodeCount,
            isListening: listenState?.isListening,
            listenPort: listenState?.listenPort,
            sslListenPort: listenState?.sslListenPort
        )
    }

    public func downloadDirectory(for id: TorrentID) throws -> URL {
        guard let tracked = torrents[id] else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        return tracked.downloadDirectory
    }

    @discardableResult
    public func deleteLocalFileData(for id: TorrentID, fileIndex: Int) throws -> URL {
        let file = try torrentFile(for: id, index: fileIndex)
        let directory = try downloadDirectory(for: id)
        let fileURL = directory.appendingPathComponent(file.path).standardizedFileURL

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            throw translatedFileSystemError(error)
        }

        emitAlert(.torrentFileDataDeleted, torrentID: id, message: "Deleted local torrent file data.")
        return fileURL
    }

    public func exportNativeResumeData(for id: TorrentID) throws -> Data {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        let data = try BridgeRuntime.exportNativeResumeData(session: session, id: id)
        emitAlert(.resumeDataExported, torrentID: id, message: "Exported native resume data.")
        return data
    }

    public func exportTorrentFile(for id: TorrentID) throws -> Data {
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            let data = try BridgeRuntime.exportTorrentFile(session: session, id: id)
            emitAlert(.torrentMetadataExported, torrentID: id, message: "Exported torrent metadata.")
            return data
        } catch let error as LibtorrentAppleError {
            if case let .nativeOperationFailed(_, message) = error,
               message.localizedCaseInsensitiveContains("metadata is not available yet")
            {
                throw LibtorrentAppleError.metadataUnavailable(id)
            }

            throw error
        }
    }

    public func exportResumeData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(resumeDataSnapshot())
            emitAlert(.resumeDataExported, message: "Exported resume data snapshot.")
            return data
        } catch {
            throw LibtorrentAppleError.resumeDataEncodingFailed(String(describing: error))
        }
    }

    public func restoreResumeData(_ snapshot: ResumeDataSnapshot) {
        configuration = snapshot.configuration
        torrents = Dictionary(
            uniqueKeysWithValues: snapshot.torrents.map {
                (
                    $0.id,
                    TrackedTorrent(
                        source: $0.source,
                        name: $0.name,
                        downloadDirectory: $0.downloadDirectory ?? defaultDownloadDirectoryURL(),
                        state: $0.state,
                        metrics: $0.metrics,
                        addedAt: $0.addedAt,
                        updatedAt: $0.updatedAt
                    )
                )
            }
        )

        if nativeSession != nil {
            try? rebuildNativeSession()
        }

        emitAlert(.resumeDataRestored, message: "Restored resume data snapshot.")
    }

    public func restoreResumeData(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let snapshot = try decoder.decode(ResumeDataSnapshot.self, from: data)
            restoreResumeData(snapshot)
        } catch {
            throw LibtorrentAppleError.resumeDataDecodingFailed(String(describing: error))
        }
    }

    private func requireRunningSession() throws -> BridgeSessionHandle {
        try BridgeRuntime.requireAvailable()

        guard isRunning, let nativeSession else {
            throw LibtorrentAppleError.sessionNotRunning
        }

        return nativeSession
    }

    private func validate(_ source: TorrentSource) throws {
        switch source.kind {
        case .magnetLink:
            guard source.location.scheme?.lowercased() == "magnet" else {
                throw LibtorrentAppleError.invalidTorrentSource(source.location)
            }
        case .torrentFile:
            guard source.location.isFileURL else {
                throw LibtorrentAppleError.invalidTorrentSource(source.location)
            }
        }
    }

    private func addNativeTorrent(
        session: BridgeSessionHandle,
        source: TorrentSource,
        downloadDirectory: URL
    ) throws -> TorrentID {
        let downloadPath = try ensureDownloadPath(downloadDirectory: downloadDirectory)

        switch source.kind {
        case .magnetLink:
            return try BridgeRuntime.addMagnet(
                session: session,
                magnetURI: source.location.absoluteString,
                downloadPath: downloadPath
            )
        case .torrentFile:
            return try BridgeRuntime.addTorrentFile(
                session: session,
                torrentFilePath: source.location.path,
                downloadPath: downloadPath
            )
        }
    }

    private func ensureDownloadDirectory(_ explicitDirectory: URL?) throws -> URL {
        let directory = explicitDirectory ?? defaultDownloadDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func ensureDownloadPath(downloadDirectory: URL) throws -> String {
        let directory = try ensureDownloadDirectory(downloadDirectory)
        return directory.path
    }

    private func defaultDownloadDirectoryURL() -> URL {
        configuration.downloadDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("LibtorrentAppleDownloads", isDirectory: true)
    }

    private func applyTrackerPresetIfNeeded(session: BridgeSessionHandle, torrentID: TorrentID) {
        let updates = normalizedTrackerPresetUpdates()
        guard !updates.isEmpty else {
            return
        }

        do {
            try BridgeRuntime.addTrackers(
                session: session,
                id: torrentID,
                trackers: updates,
                forceReannounce: true
            )
            emitAlert(
                .torrentTrackerAdded,
                torrentID: torrentID,
                message: "Applied tracker preset (\(updates.count) trackers)."
            )
        } catch {
            emitAlert(
                .torrentTrackerWarning,
                torrentID: torrentID,
                message: "Tracker preset apply failed: \(error.localizedDescription)"
            )
        }
    }

    private func normalizedTrackerPresetUpdates() -> [TorrentTrackerUpdate] {
        var seen: Set<String> = []
        var urls: [String] = []

        for rawURL in configuration.trackerPresetURLs {
            let normalizedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedURL.isEmpty, !seen.contains(normalizedURL) else {
                continue
            }
            seen.insert(normalizedURL)
            urls.append(normalizedURL)
        }

        return urls.enumerated().map { index, url in
            TorrentTrackerUpdate(url: url, tier: index)
        }
    }

    private func makeRehydrationSeeds(from previousSession: BridgeSessionHandle?) -> [RehydrationSeed] {
        torrents
            .sorted { lhs, rhs in
                lhs.value.addedAt < rhs.value.addedAt
            }
            .map { id, tracked in
                let nativeResumeData: Data?
                if let previousSession {
                    nativeResumeData = try? BridgeRuntime.exportNativeResumeData(session: previousSession, id: id)
                } else {
                    nativeResumeData = nil
                }

                return RehydrationSeed(
                    tracked: tracked,
                    nativeResumeData: nativeResumeData
                )
            }
    }

    private func rehydrateTrackedTorrents(from previousSession: BridgeSessionHandle? = nil) throws {
        guard !torrents.isEmpty, let nativeSession else {
            return
        }

        let rehydrationSeeds = makeRehydrationSeeds(from: previousSession)
        var rebuilt: [TorrentID: TrackedTorrent] = [:]
        for seed in rehydrationSeeds {
            let tracked = seed.tracked
            let recreatedID: TorrentID

            if let nativeResumeData = seed.nativeResumeData {
                recreatedID = try BridgeRuntime.addResumeData(
                    session: nativeSession,
                    resumeData: nativeResumeData,
                    downloadPath: try ensureDownloadPath(downloadDirectory: tracked.downloadDirectory)
                )
            } else {
                recreatedID = try addNativeTorrent(
                    session: nativeSession,
                    source: tracked.source,
                    downloadDirectory: tracked.downloadDirectory
                )
                applyTrackerPresetIfNeeded(session: nativeSession, torrentID: recreatedID)
            }

            if tracked.state == .paused {
                try BridgeRuntime.pauseTorrent(session: nativeSession, id: recreatedID)
            }

            let nativeStatus = try BridgeRuntime.status(session: nativeSession, id: recreatedID)
            let status = materializeStatus(id: recreatedID, tracked: tracked, nativeStatus: nativeStatus)
            rebuilt[recreatedID] = TrackedTorrent(
                source: status.source,
                name: status.name,
                downloadDirectory: tracked.downloadDirectory,
                state: status.state,
                metrics: status.metrics,
                addedAt: tracked.addedAt,
                updatedAt: tracked.updatedAt
            )
        }

        torrents = rebuilt
    }

    private func rebuildNativeSession() throws {
        let replacement: BridgeSessionHandle
        do {
            replacement = try BridgeRuntime.createSession(configuration: configuration)
        } catch {
            throw translatedConfigurationError(error)
        }
        let previous = nativeSession
        stopNativeAlertPolling()
        nativeSession = replacement

        do {
            try rehydrateTrackedTorrents(from: previous)
            isRunning = true
            startNativeAlertPolling()
            BridgeRuntime.destroySession(previous)
        } catch {
            BridgeRuntime.destroySession(replacement)
            nativeSession = previous
            if let previous {
                nativeSession = previous
                startNativeAlertPolling()
            }
            throw error
        }
    }

    private func startThroughputOptimizerTaskIfNeeded() {
        guard throughputOptimizerTask == nil else {
            return
        }

        throughputOptimizerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let interval = await self.throughputOptimizerPolicy?.sampleIntervalSeconds ?? 2
                do {
                    try await AsyncTiming.sleep(seconds: interval)
                } catch {
                    return
                }

                await self.runThroughputOptimizerTick()
            }
        }
    }

    private func runThroughputOptimizerTick() {
        guard isRunning, throughputOptimizerPolicy != nil else {
            return
        }

        let statuses = allTorrentStatuses()
        let downloading = statuses.filter { status in
            status.state == .running && status.metrics.progress < 1
        }

        guard !downloading.isEmpty else {
            throughputOptimizerState.consecutiveLowSpeedWindows = 0
            throughputOptimizerState.consecutiveZeroSpeedWindows = 0
            if throughputOptimizerState.isBoosted {
                throughputOptimizerState.stableRecoveryWindows += 1
                tryRestoreThroughputOptimizerBaseline(force: false)
            }
            return
        }

        let aggregateDownloadRate = downloading.reduce(0 as Int64) { partial, status in
            partial + status.metrics.downloadRateBytesPerSecond
        }

        if aggregateDownloadRate == 0 {
            throughputOptimizerState.consecutiveZeroSpeedWindows += 1
        } else {
            throughputOptimizerState.consecutiveZeroSpeedWindows = 0
        }

        if let lowSpeedThreshold = throughputOptimizerPolicy?.lowSpeedThresholdBytesPerSecond,
           aggregateDownloadRate < lowSpeedThreshold
        {
            throughputOptimizerState.consecutiveLowSpeedWindows += 1
        } else {
            throughputOptimizerState.consecutiveLowSpeedWindows = 0
        }

        if let recoveryThreshold = throughputOptimizerPolicy?.recoverySpeedThresholdBytesPerSecond,
           aggregateDownloadRate >= recoveryThreshold
        {
            throughputOptimizerState.stableRecoveryWindows += 1
        } else {
            throughputOptimizerState.stableRecoveryWindows = 0
        }

        guard canRunThroughputOptimizerAction() else {
            return
        }

        var triggered = false
        if let zeroWindows = throughputOptimizerPolicy?.consecutiveZeroSpeedWindowsForReannounce,
           throughputOptimizerState.consecutiveZeroSpeedWindows >= zeroWindows
        {
            let reannounced = reannounceDownloadingTorrents(downloading)
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_throughput_optimizer_reannounce",
                message: "Throughput optimizer reannounced \(reannounced) downloading torrents after zero-speed windows."
            )
            throughputOptimizerState.consecutiveZeroSpeedWindows = 0
            triggered = true
        }

        if let lowWindows = throughputOptimizerPolicy?.consecutiveLowSpeedWindowsForBoost,
           throughputOptimizerState.consecutiveLowSpeedWindows >= lowWindows
        {
            applyThroughputOptimizerBoost()
            throughputOptimizerState.consecutiveLowSpeedWindows = 0
            triggered = true
        }

        if triggered {
            throughputOptimizerState.lastActionAt = Date()
        }

        tryRestoreThroughputOptimizerBaseline(force: false)
    }

    private func canRunThroughputOptimizerAction() -> Bool {
        guard let cooldown = throughputOptimizerPolicy?.cooldownSeconds else {
            return false
        }

        guard let lastActionAt = throughputOptimizerState.lastActionAt else {
            return true
        }

        return Date().timeIntervalSince(lastActionAt) >= cooldown
    }

    private func reannounceDownloadingTorrents(_ statuses: [TorrentStatus]) -> Int {
        guard let session = nativeSession else {
            return 0
        }

        var succeeded = 0
        for status in statuses {
            do {
                try BridgeRuntime.forceReannounce(
                    session: session,
                    id: status.id,
                    after: 0,
                    trackerIndex: nil,
                    ignoreMinimumInterval: true
                )
                succeeded += 1
            } catch {
                emitAlert(
                    .torrentTrackerWarning,
                    torrentID: status.id,
                    message: "Throughput optimizer reannounce failed: \(error.localizedDescription)"
                )
            }
        }
        return succeeded
    }

    private func applyThroughputOptimizerBoost() {
        guard let policy = throughputOptimizerPolicy else {
            return
        }

        var boosted = configuration
        boosted.connectionSpeed = max(boosted.connectionSpeed, policy.boostedConnectionSpeed)
        boosted.torrentConnectBoost = max(boosted.torrentConnectBoost, policy.boostedTorrentConnectBoost)
        boosted.maxOutgoingRequestQueueSize = max(
            boosted.maxOutgoingRequestQueueSize,
            policy.boostedMaxOutgoingRequestQueueSize
        )
        boosted.maxAllowedIncomingRequestQueueSize = max(
            boosted.maxAllowedIncomingRequestQueueSize,
            policy.boostedMaxAllowedIncomingRequestQueueSize
        )
        boosted.peerTurnover = maxOptional(current: boosted.peerTurnover, proposed: policy.boostedPeerTurnover)
        boosted.peerTurnoverCutoff = maxOptional(current: boosted.peerTurnoverCutoff, proposed: policy.boostedPeerTurnoverCutoff)
        boosted.peerTurnoverInterval = maxOptional(
            current: boosted.peerTurnoverInterval,
            proposed: policy.boostedPeerTurnoverInterval
        )

        do {
            throughputOptimizerInternalApply = true
            try applyConfiguration(boosted)
            throughputOptimizerState.isBoosted = true
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_throughput_optimizer_boost_applied",
                message: "Applied throughput optimizer boost."
            )
        } catch {
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_throughput_optimizer_boost_failed",
                message: "Throughput optimizer boost failed: \(error.localizedDescription)"
            )
        }
        throughputOptimizerInternalApply = false
    }

    private func tryRestoreThroughputOptimizerBaseline(force: Bool) {
        guard throughputOptimizerState.isBoosted,
              let policy = throughputOptimizerPolicy,
              let baseline = throughputOptimizerBaseConfiguration
        else {
            return
        }

        if !force && throughputOptimizerState.stableRecoveryWindows < policy.stableRecoveryWindowsForRestore {
            return
        }

        do {
            throughputOptimizerInternalApply = true
            try applyConfiguration(baseline)
            throughputOptimizerState.isBoosted = false
            throughputOptimizerState.stableRecoveryWindows = 0
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_throughput_optimizer_baseline_restored",
                message: "Restored throughput optimizer baseline configuration."
            )
        } catch {
            emitAlert(
                .nativeEvent,
                nativeEventName: "session_throughput_optimizer_restore_failed",
                message: "Throughput optimizer restore failed: \(error.localizedDescription)"
            )
        }
        throughputOptimizerInternalApply = false
    }

    private func maxOptional(current: Int?, proposed: Int?) -> Int? {
        switch (current, proposed) {
        case let (.some(current), .some(proposed)):
            return max(current, proposed)
        case let (.some(current), .none):
            return current
        case let (.none, .some(proposed)):
            return proposed
        case (.none, .none):
            return nil
        }
    }

    private func startNativeAlertPolling() {
        stopNativeAlertPolling()

        alertPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let shouldContinue = await self.drainNativeAlerts()
                if !shouldContinue {
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func stopNativeAlertPolling() {
        alertPollTask?.cancel()
        alertPollTask = nil
    }

    private func drainNativeAlerts() -> Bool {
        guard isRunning, let session = nativeSession else {
            return false
        }

        do {
            while let nativeAlert = try BridgeRuntime.popAlert(session: session) {
                let kind = mappedAlertKind(for: nativeAlert)
                emitAlert(
                    kind,
                    torrentID: nativeAlert.torrentID,
                    nativeTypeCode: nativeAlert.typeCode,
                    nativeEventName: nativeAlert.name,
                    message: nativeAlert.message
                )
            }

            return true
        } catch {
            emitAlert(
                .nativeEvent,
                nativeEventName: "native_alert_poll_failed",
                message: "Native alert polling failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func resolvedName(for source: TorrentSource, explicitName: String?) -> String {
        if let explicitName, !explicitName.isEmpty {
            return explicitName
        }

        if let displayName = source.displayName, !displayName.isEmpty {
            return displayName
        }

        return source.location.lastPathComponent.isEmpty ? source.location.absoluteString : source.location.lastPathComponent
    }

    private func materializeCachedStatus(id: TorrentID, tracked: TrackedTorrent) -> TorrentStatus {
        TorrentStatus(
            id: id,
            name: tracked.name,
            source: tracked.source,
            downloadDirectory: tracked.downloadDirectory,
            state: tracked.state,
            metrics: tracked.metrics,
            addedAt: tracked.addedAt,
            updatedAt: tracked.updatedAt
        )
    }

    private func materializeStatus(
        id: TorrentID,
        tracked: TrackedTorrent,
        nativeStatus: libtorrent_apple_torrent_status_t
    ) -> TorrentStatus {
        let resolvedName = tracked.name.isEmpty ? (BridgeRuntime.nativeName(from: nativeStatus) ?? tracked.name) : tracked.name
        let resolvedState: TorrentState

        switch tracked.state {
        case .paused, .stopped, .removed:
            resolvedState = tracked.state
        case .running, .idle:
            resolvedState = BridgeRuntime.state(from: nativeStatus)
        }

        return TorrentStatus(
            id: id,
            name: resolvedName,
            source: tracked.source,
            downloadDirectory: tracked.downloadDirectory,
            state: resolvedState,
            metrics: BridgeRuntime.metrics(from: nativeStatus),
            addedAt: tracked.addedAt,
            updatedAt: Date()
        )
    }

    private func syncTrackedTorrent(with status: TorrentStatus) {
        guard var tracked = torrents[status.id] else {
            return
        }

        tracked.name = status.name
        tracked.state = status.state
        tracked.metrics = status.metrics
        tracked.updatedAt = status.updatedAt
        torrents[status.id] = tracked
    }

    private func syncTrackedTorrentDownloadDirectory(id: TorrentID, directory: URL) {
        guard var tracked = torrents[id] else {
            return
        }

        tracked.downloadDirectory = directory
        tracked.updatedAt = Date()
        torrents[id] = tracked
    }

    private func translatedMetadataError(_ error: Error, torrentID: TorrentID) -> Error {
        guard let error = error as? LibtorrentAppleError else {
            return error
        }

        if case let .nativeOperationFailed(_, message) = error,
           message.localizedCaseInsensitiveContains("metadata is not available yet")
        {
            return LibtorrentAppleError.metadataUnavailable(torrentID)
        }

        return error
    }

    private func translatedConfigurationError(_ error: Error) -> Error {
        guard let error = error as? LibtorrentAppleError,
              case let .nativeOperationFailed(_, message) = error
        else {
            return error
        }

        return LibtorrentAppleError.configurationInvalid(message)
    }

    private func translatedTrackerError(_ error: Error) -> Error {
        guard let error = error as? LibtorrentAppleError,
              case let .nativeOperationFailed(_, message) = error
        else {
            return error
        }

        return LibtorrentAppleError.trackerOperationFailed(message)
    }

    private func translatedStorageError(_ error: Error) -> Error {
        guard let error = error as? LibtorrentAppleError,
              case let .nativeOperationFailed(_, message) = error
        else {
            return error
        }

        return LibtorrentAppleError.storageOperationFailed(message)
    }

    private func translatedPieceControlError(_ error: Error, torrentID: TorrentID) -> Error {
        let translated = translatedMetadataError(error, torrentID: torrentID)
        guard let translated = translated as? LibtorrentAppleError,
              case let .nativeOperationFailed(_, message) = translated
        else {
            return translated
        }

        return LibtorrentAppleError.pieceControlFailed(message)
    }

    private func translatedFileSystemError(_ error: Error) -> Error {
        LibtorrentAppleError.fileSystemOperationFailed(error.localizedDescription)
    }

    private func mappedAlertKind(for nativeAlert: BridgeNativeAlert) -> TorrentAlert.Kind {
        switch nativeAlert.name.lowercased() {
        case "metadata_received":
            return .torrentMetadataReceived
        case "state_changed":
            return .torrentStateChanged
        case "torrent_finished":
            return .torrentFinished
        case "tracker_warning":
            return .torrentTrackerWarning
        case "tracker_error":
            return .torrentTrackerError
        case "performance":
            return .torrentPerformanceWarning
        case "save_resume_data":
            return .resumeDataExported
        case "save_resume_data_failed":
            return .resumeDataExportFailed
        default:
            return .nativeEvent
        }
    }

    private func emitAlert(
        _ kind: TorrentAlert.Kind,
        torrentID: TorrentID? = nil,
        nativeTypeCode: Int32? = nil,
        nativeEventName: String? = nil,
        message: String
    ) {
        alertContinuation.yield(
            TorrentAlert(
                kind: kind,
                torrentID: torrentID,
                nativeTypeCode: nativeTypeCode,
                nativeEventName: nativeEventName,
                message: message
            )
        )
    }
}
