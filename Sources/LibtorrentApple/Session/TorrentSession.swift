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

public actor TorrentSession {
    public private(set) var configuration: SessionConfiguration
    public private(set) var isRunning = false

    private var nativeSession: BridgeSessionHandle?
    private var alertPollTask: Task<Void, Never>?
    private var torrents: [TorrentID: TrackedTorrent] = [:]
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
        pollInterval: Duration = .seconds(1),
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
                    try? await Task.sleep(for: pollInterval)
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
        pollInterval: Duration = .seconds(1),
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

    public func stop() {
        guard isRunning else {
            return
        }

        stopNativeAlertPolling()
        BridgeRuntime.destroySession(nativeSession)
        nativeSession = nil
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
        let session = try requireRunningSession()
        guard torrents[id] != nil else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        do {
            try BridgeRuntime.addTracker(session: session, id: id, tracker: tracker)
            emitAlert(.torrentTrackerAdded, torrentID: id, message: "Added torrent tracker.")
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
            guard let nativeStatus = try? BridgeRuntime.status(session: session, id: id) else {
                return materializeCachedStatus(id: id, tracked: tracked)
            }

            let status = materializeStatus(id: id, tracked: tracked, nativeStatus: nativeStatus)
            syncTrackedTorrent(with: status)
            return status
        }
    }

    public func resumeDataSnapshot() -> ResumeDataSnapshot {
        ResumeDataSnapshot(configuration: configuration, torrents: allTorrentStatuses())
    }

    public func totalStats() -> TorrentDownloaderStats {
        TorrentDownloaderStats(statuses: allTorrentStatuses())
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

    private func rehydrateTrackedTorrents() throws {
        guard !torrents.isEmpty, let nativeSession else {
            return
        }

        let existingTorrents = torrents.sorted { lhs, rhs in
            lhs.value.addedAt < rhs.value.addedAt
        }

        var rebuilt: [TorrentID: TrackedTorrent] = [:]
        for (_, tracked) in existingTorrents {
            let recreatedID = try addNativeTorrent(
                session: nativeSession,
                source: tracked.source,
                downloadDirectory: tracked.downloadDirectory
            )
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
            try rehydrateTrackedTorrents()
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
        case .running, .paused, .stopped, .removed:
            resolvedState = tracked.state
        case .idle:
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
