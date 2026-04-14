import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor TorrentDownloader {
    public let backendInfo: TorrentBackendInfo
    public let rootDirectory: URL
    public private(set) var configuration: SessionConfiguration

    private let sessionStorage: TorrentSession
    private var persistentStateSaveTask: Task<URL?, Never>?
    private var lastPersistedPersistentStateRevision: UInt64 = 0

    public init(
        configuration: SessionConfiguration = .default,
        rootDirectory: URL? = nil
    ) {
        let resolvedRootDirectory =
            rootDirectory
            ?? configuration.downloadDirectory?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("LibtorrentApple", isDirectory: true)

        var resolvedConfiguration = configuration
        if resolvedConfiguration.downloadDirectory == nil {
            resolvedConfiguration.downloadDirectory = resolvedRootDirectory.appendingPathComponent("Downloads", isDirectory: true)
        }

        self.backendInfo = LibtorrentApple.backendInfo
        self.rootDirectory = resolvedRootDirectory
        self.configuration = resolvedConfiguration
        self.sessionStorage = TorrentSession(configuration: resolvedConfiguration)
    }

    public func session() -> TorrentSession {
        sessionStorage
    }

    public func alerts() async -> AsyncStream<TorrentAlert> {
        await sessionStorage.alerts()
    }

    public func start() async throws {
        try createRequiredDirectories()
        try await sessionStorage.start()
    }

    public func applyConfiguration(_ configuration: SessionConfiguration) async throws {
        try await sessionStorage.applyConfiguration(configuration)
        self.configuration = configuration
    }

    public func applyProfile(_ profile: SessionProfile) async throws {
        let updated = configuration.applyingProfile(profile)
        try await applyConfiguration(updated)
    }

    public func scheduleConfigurationApply(
        _ configuration: SessionConfiguration,
        debounceInterval: TimeInterval = 0.2
    ) async {
        self.configuration = configuration
        await sessionStorage.scheduleConfigurationApply(configuration, debounceInterval: debounceInterval)
    }

    @discardableResult
    public func flushDeferredConfigurationApply() async -> Bool {
        let applied = await sessionStorage.flushDeferredConfigurationApply()
        if applied {
            self.configuration = await sessionStorage.configuration
        }
        return applied
    }

    public func setPeerFilters(
        blockedCIDRs: [String],
        allowedCIDRs: [String] = []
    ) async throws {
        var updated = configuration
        updated.peerBlockedCIDRs = blockedCIDRs
        updated.peerAllowedCIDRs = allowedCIDRs
        try await applyConfiguration(updated)
    }

    public func clearPeerFilters() async throws {
        try await setPeerFilters(blockedCIDRs: [], allowedCIDRs: [])
    }

    public func setTransportBehavior(_ behavior: SessionTransportBehavior) async throws {
        let updated = configuration.applyingTransportBehavior(behavior)
        try await applyConfiguration(updated)
    }

    public func scheduleTransportBehaviorApply(
        _ behavior: SessionTransportBehavior,
        debounceInterval: TimeInterval = 0.2
    ) async {
        let updated = configuration.applyingTransportBehavior(behavior)
        self.configuration = updated
        await sessionStorage.scheduleConfigurationApply(updated, debounceInterval: debounceInterval)
    }

    public func startThroughputOptimizer(
        policy: SessionThroughputOptimizerPolicy = .default
    ) async {
        await sessionStorage.startThroughputOptimizer(policy: policy)
    }

    public func stopThroughputOptimizer(restoreBaseline: Bool = true) async {
        await sessionStorage.stopThroughputOptimizer(restoreBaseline: restoreBaseline)
        self.configuration = await sessionStorage.configuration
    }

    public func isThroughputOptimizerEnabled() async -> Bool {
        await sessionStorage.isThroughputOptimizerEnabled()
    }

    public func stop() async {
        persistentStateSaveTask?.cancel()
        persistentStateSaveTask = nil
        await sessionStorage.stop()
    }

    @discardableResult
    public func reannounceAllTorrents(
        after seconds: Int = 0,
        ignoreMinimumInterval: Bool = true
    ) async throws -> Int {
        try await sessionStorage.reannounceAllTorrents(after: seconds, ignoreMinimumInterval: ignoreMinimumInterval)
    }

    @discardableResult
    public func reopenNetworkSockets(remapPorts: Bool = true) async throws -> Bool {
        try await sessionStorage.reopenNetworkSockets(remapPorts: remapPorts)
    }

    @discardableResult
    public func handleNetworkPathChanged() async throws -> Int {
        try await sessionStorage.handleNetworkPathChanged()
    }

    @discardableResult
    public func handleSystemWakeupDetected() async throws -> Int {
        try await sessionStorage.handleSystemWakeupDetected()
    }

    public func totalStats() async -> TorrentDownloaderStats {
        await sessionStorage.totalStats()
    }

    public func sessionDiagnostics() async throws -> TorrentSessionDiagnostics {
        try await sessionStorage.sessionDiagnostics()
    }

    public func statsUpdates(
        pollInterval: TimeInterval = 1,
        emitInitialValue: Bool = true,
        onlyChanges: Bool = true
    ) async -> AsyncStream<TorrentDownloaderStats> {
        await sessionStorage.statsUpdates(
            pollInterval: pollInterval,
            emitInitialValue: emitInitialValue,
            onlyChanges: onlyChanges
        )
    }

    public func torrentStatuses() async -> [TorrentStatus] {
        await sessionStorage.allTorrentStatuses()
    }

    public func torrentHandles() async -> [TorrentHandle] {
        await sessionStorage.handles()
    }

    public func addTorrent(
        from source: TorrentSource,
        options: AddTorrentOptions = .default
    ) async throws -> TorrentHandle {
        try createRequiredDirectories()
        return try await sessionStorage.addTorrentHandle(from: source, options: options)
    }

    public func addTorrent(
        from encodedTorrent: EncodedTorrentInfo,
        options: AddTorrentOptions = .default
    ) async throws -> TorrentHandle {
        try createRequiredDirectories()

        let storedURL = try persistEncodedTorrent(encodedTorrent)
        let displayName = options.displayName ?? encodedTorrent.suggestedName
        let source = TorrentSource.torrentFile(storedURL, displayName: displayName)

        return try await sessionStorage.addTorrentHandle(from: source, options: options)
    }

    public func addTorrent(
        fromNativeResumeData data: Data,
        options: AddTorrentOptions = .default
    ) async throws -> TorrentHandle {
        try createRequiredDirectories()
        return try await sessionStorage.addTorrentHandle(fromNativeResumeData: data, options: options)
    }

    public func fetchTorrent(
        from url: URL,
        timeout: TimeInterval = 30,
        pollInterval: TimeInterval = 0.25
    ) async throws -> EncodedTorrentInfo {
        guard let scheme = url.scheme?.lowercased() else {
            throw LibtorrentAppleError.unsupportedURLScheme(url.absoluteString)
        }

        switch scheme {
        case "file":
            return EncodedTorrentInfo(
                data: try Data(contentsOf: url),
                sourceURL: url,
                suggestedName: url.deletingPathExtension().lastPathComponent
            )
        case "http", "https":
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200 ... 299).contains(httpResponse.statusCode)
                {
                    throw LibtorrentAppleError.networkTransferFailed("HTTP status \(httpResponse.statusCode)")
                }

                return EncodedTorrentInfo(
                    data: data,
                    sourceURL: url,
                    suggestedName: url.deletingPathExtension().lastPathComponent
                )
            } catch let error as LibtorrentAppleError {
                throw error
            } catch {
                throw LibtorrentAppleError.networkTransferFailed(error.localizedDescription)
            }
        case "magnet":
            return try await fetchMagnetMetadata(from: url, timeout: timeout, pollInterval: pollInterval)
        default:
            throw LibtorrentAppleError.unsupportedURLScheme(scheme)
        }
    }

    @discardableResult
    public func savePersistentState() async throws -> URL {
        try createRequiredDirectories()

        let exportContext = await sessionStorage.persistentStateExportContext()
        let handlesByID = Dictionary(
            uniqueKeysWithValues: await sessionStorage.handles().map { ($0.id, $0) }
        )

        var trackedArtifacts: [PersistentStateTrackedArtifact] = []
        var manifestTorrents: [PersistentStateManifestTorrent] = []

        for descriptor in exportContext.torrents {
            let status = descriptor.status
            let handle = handlesByID[status.id]
            let resumeDataURL = try await persistResumeDataArtifact(
                for: status,
                handle: handle,
                existingArtifactURL: descriptor.persistedResumeDataURL
            )
            let torrentFileURL = try await persistTorrentFileArtifact(
                for: status,
                handle: handle,
                existingArtifactURL: descriptor.persistedTorrentFileURL
            )

            trackedArtifacts.append(
                PersistentStateTrackedArtifact(
                    id: status.id,
                    resumeDataURL: resumeDataURL,
                    torrentFileURL: torrentFileURL
                )
            )
            manifestTorrents.append(
                PersistentStateManifestTorrent(
                    id: status.id,
                    name: status.name,
                    source: status.source,
                    downloadDirectory: status.downloadDirectory ?? defaultSaveDirectory(),
                    desiredState: status.state == .paused ? .paused : .running,
                    addedAt: status.addedAt,
                    updatedAt: status.updatedAt,
                    resumeDataFileName: resumeDataURL?.lastPathComponent,
                    torrentFileName: torrentFileURL?.lastPathComponent
                )
            )
        }

        let manifest = PersistentStateManifest(
            configuration: exportContext.configuration,
            torrents: manifestTorrents
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let manifestData = try encoder.encode(manifest)
        let manifestURL = persistentStateManifestURL()
        try manifestData.write(to: manifestURL, options: .atomic)
        try cleanupPersistentStateArtifacts(for: manifest)

        await sessionStorage.applyPersistentArtifacts(trackedArtifacts)

        let endRevision = await sessionStorage.persistentStateRevisionValue()
        lastPersistedPersistentStateRevision = exportContext.revision
        if endRevision == exportContext.revision {
            configuration = exportContext.configuration
        } else {
            configuration = await sessionStorage.configuration
        }

        return manifestURL
    }

    public func restorePersistentState() async throws -> PersistentStateRestoreReport {
        let manifestURL = persistentStateManifestURL()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return PersistentStateRestoreReport(entries: [])
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)
        guard manifest.version == PersistentStateManifest.currentVersion else {
            throw LibtorrentAppleError.resumeDataDecodingFailed(
                "Unsupported persistent state version \(manifest.version)."
            )
        }

        let candidates = manifest.torrents.map { torrent in
            PersistentStateRestoreCandidate(
                manifestTorrent: torrent,
                resumeDataURL: resolvePersistentArtifactURL(
                    fileName: torrent.resumeDataFileName,
                    in: persistentResumeDataDirectoryURL()
                ),
                torrentFileURL: resolvePersistentArtifactURL(
                    fileName: torrent.torrentFileName,
                    in: persistentTorrentStateFilesDirectoryURL()
                )
            )
        }

        let report = try await sessionStorage.restorePersistentState(
            configuration: manifest.configuration,
            candidates: candidates
        )
        configuration = await sessionStorage.configuration
        lastPersistedPersistentStateRevision = await sessionStorage.persistentStateRevisionValue()
        return report
    }

    public func hasPendingPersistentStateChanges() async -> Bool {
        await sessionStorage.persistentStateRevisionValue() != lastPersistedPersistentStateRevision
    }

    public func schedulePersistentStateSave(
        debounceInterval: TimeInterval = 0.5
    ) async {
        persistentStateSaveTask?.cancel()
        let downloader = self
        persistentStateSaveTask = Task {
            do {
                try await AsyncTiming.sleep(seconds: debounceInterval)
            } catch {
                return nil
            }

            return try? await downloader.flushScheduledPersistentStateSave()
        }
    }

    @discardableResult
    public func flushScheduledPersistentStateSave() async throws -> URL? {
        persistentStateSaveTask = nil
        guard await hasPendingPersistentStateChanges() else {
            return nil
        }

        return try await savePersistentState()
    }

    public func managedTorrentFiles() throws -> [URL] {
        try sortedFiles(in: torrentFilesDirectoryURL(), pathExtension: "torrent")
    }

    public func saveDirectory(for handle: TorrentHandle) async throws -> URL {
        try await handle.downloadDirectory()
    }

    public func saveDirectories() async -> [URL] {
        let statuses = await sessionStorage.allTorrentStatuses()
        let directories = statuses.compactMap(\.downloadDirectory)
        return Array(Set(directories)).sorted { $0.path < $1.path }
    }

    public func defaultSaveDirectory() -> URL {
        (
            configuration.downloadDirectory
            ?? rootDirectory.appendingPathComponent("Downloads", isDirectory: true)
        ).standardizedFileURL
    }

    private func fetchMagnetMetadata(
        from magnetURL: URL,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async throws -> EncodedTorrentInfo {
        var scratchConfiguration = configuration
        scratchConfiguration.downloadDirectory = rootDirectory.appendingPathComponent("MetadataScratch", isDirectory: true)

        let scratchSession = TorrentSession(configuration: scratchConfiguration)
        try await scratchSession.start()

        do {
            let handle = try await scratchSession.addTorrentHandle(
                from: .magnetLink(magnetURL),
                options: AddTorrentOptions(downloadDirectory: scratchConfiguration.downloadDirectory)
            )

            let deadline = AsyncTiming.deadline(after: timeout)
            while Date() < deadline {
                do {
                    let data = try await handle.exportTorrentFile()
                    let status = try await handle.status()
                    await scratchSession.stop()
                    return EncodedTorrentInfo(
                        data: data,
                        sourceURL: magnetURL,
                        suggestedName: status.name
                    )
                } catch let error as LibtorrentAppleError {
                    if case .metadataUnavailable = error {
                        try await AsyncTiming.sleep(seconds: pollInterval)
                        continue
                    }

                    await scratchSession.stop()
                    throw error
                }
            }

            await scratchSession.stop()
            throw LibtorrentAppleError.operationTimedOut("Timed out while fetching torrent metadata from magnet link.")
        } catch {
            await scratchSession.stop()
            throw error
        }
    }

    private func createRequiredDirectories() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: defaultSaveDirectory(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: torrentFilesDirectoryURL(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: persistentStateDirectoryURL(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: persistentResumeDataDirectoryURL(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: persistentTorrentStateFilesDirectoryURL(), withIntermediateDirectories: true)
    }

    private func torrentFilesDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("TorrentFiles", isDirectory: true).standardizedFileURL
    }

    private func persistentStateDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("PersistentState", isDirectory: true).standardizedFileURL
    }

    private func persistentStateManifestURL() -> URL {
        persistentStateDirectoryURL().appendingPathComponent("manifest.json").standardizedFileURL
    }

    private func persistentResumeDataDirectoryURL() -> URL {
        persistentStateDirectoryURL().appendingPathComponent("ResumeData", isDirectory: true).standardizedFileURL
    }

    private func persistentTorrentStateFilesDirectoryURL() -> URL {
        persistentStateDirectoryURL().appendingPathComponent("TorrentFiles", isDirectory: true).standardizedFileURL
    }

    private func persistentResumeDataArtifactURL(for id: TorrentID) -> URL {
        persistentResumeDataDirectoryURL()
            .appendingPathComponent("\(id.rawValue).resume")
            .standardizedFileURL
    }

    private func persistentTorrentFileArtifactURL(for id: TorrentID) -> URL {
        persistentTorrentStateFilesDirectoryURL()
            .appendingPathComponent("\(id.rawValue).torrent")
            .standardizedFileURL
    }

    private func resolvePersistentArtifactURL(fileName: String?, in directory: URL) -> URL? {
        guard let fileName, !fileName.isEmpty else {
            return nil
        }

        let url = directory.appendingPathComponent(fileName).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }

    private func persistEncodedTorrent(_ encodedTorrent: EncodedTorrentInfo) throws -> URL {
        guard !encodedTorrent.data.isEmpty else {
            throw LibtorrentAppleError.invalidTorrentData("Encoded torrent data was empty.")
        }

        let baseName = sanitizeFileStem(
            encodedTorrent.suggestedName
                ?? encodedTorrent.sourceURL?.deletingPathExtension().lastPathComponent
                ?? "torrent"
        )
        let fileURL = torrentFilesDirectoryURL()
            .appendingPathComponent("\(baseName)-\(UUID().uuidString).torrent")
            .standardizedFileURL
        try encodedTorrent.data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func persistResumeDataArtifact(
        for status: TorrentStatus,
        handle: TorrentHandle?,
        existingArtifactURL: URL?
    ) async throws -> URL? {
        let artifactURL = persistentResumeDataArtifactURL(for: status.id)

        if let handle {
            do {
                let nativeResumeData = try await handle.exportResumeData()
                try nativeResumeData.write(to: artifactURL, options: .atomic)
                return artifactURL
            } catch {
                // Fall back to the last good artifact when the session is not running or export fails.
            }
        }

        return try copyPersistentArtifactIfAvailable(from: existingArtifactURL, to: artifactURL)
    }

    private func persistTorrentFileArtifact(
        for status: TorrentStatus,
        handle: TorrentHandle?,
        existingArtifactURL: URL?
    ) async throws -> URL? {
        let artifactURL = persistentTorrentFileArtifactURL(for: status.id)

        if let handle {
            do {
                let torrentFileData = try await handle.exportTorrentFile()
                try torrentFileData.write(to: artifactURL, options: .atomic)
                return artifactURL
            } catch let error as LibtorrentAppleError {
                if case .metadataUnavailable = error {
                    // Fall through to persisted/local .torrent fallbacks.
                }
            } catch {
                // Fall through to persisted/local .torrent fallbacks.
            }
        }

        if let copiedArtifactURL = try copyPersistentArtifactIfAvailable(from: existingArtifactURL, to: artifactURL) {
            return copiedArtifactURL
        }

        if status.source.kind == .torrentFile,
           status.source.location.isFileURL,
           FileManager.default.fileExists(atPath: status.source.location.path)
        {
            return try copyPersistentArtifact(from: status.source.location, to: artifactURL)
        }

        return nil
    }

    private func copyPersistentArtifactIfAvailable(
        from sourceURL: URL?,
        to destinationURL: URL
    ) throws -> URL? {
        guard let sourceURL,
              FileManager.default.fileExists(atPath: sourceURL.path)
        else {
            return nil
        }

        return try copyPersistentArtifact(from: sourceURL, to: destinationURL)
    }

    private func copyPersistentArtifact(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws -> URL {
        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return destinationURL
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func cleanupPersistentStateArtifacts(for manifest: PersistentStateManifest) throws {
        let expectedResumeDataFiles = Set(manifest.torrents.compactMap(\.resumeDataFileName))
        let expectedTorrentFiles = Set(manifest.torrents.compactMap(\.torrentFileName))

        try removeUnexpectedArtifacts(
            in: persistentResumeDataDirectoryURL(),
            expectedFileNames: expectedResumeDataFiles
        )
        try removeUnexpectedArtifacts(
            in: persistentTorrentStateFilesDirectoryURL(),
            expectedFileNames: expectedTorrentFiles
        )
    }

    private func removeUnexpectedArtifacts(
        in directory: URL,
        expectedFileNames: Set<String>
    ) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }

        for url in try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) where !expectedFileNames.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func sortedFiles(in directory: URL, pathExtension: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { $0.pathExtension.lowercased() == pathExtension.lowercased() }
            .map(\.standardizedFileURL)
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return lhsDate < rhsDate
            }
    }

    private func sanitizeFileStem(_ value: String) -> String {
        let scalarView = value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }

            return "-"
        }

        let sanitized = String(scalarView).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? "torrent" : sanitized
    }
}
