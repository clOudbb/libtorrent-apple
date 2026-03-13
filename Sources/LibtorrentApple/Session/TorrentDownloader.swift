import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor TorrentDownloader {
    public let backendInfo: TorrentBackendInfo
    public let rootDirectory: URL
    public private(set) var configuration: SessionConfiguration

    private let sessionStorage: TorrentSession

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

    public func stop() async {
        await sessionStorage.stop()
    }

    public func totalStats() async -> TorrentDownloaderStats {
        await sessionStorage.totalStats()
    }

    public func statsUpdates(
        pollInterval: Duration = .seconds(1),
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
        timeout: Duration = .seconds(30),
        pollInterval: Duration = .milliseconds(250)
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
    public func persistResumeSnapshot(named name: String = "default") async throws -> URL {
        try createRequiredDirectories()

        let snapshotData = try await sessionStorage.exportResumeData()
        let snapshotURL = snapshotFileURL(for: name)
        try snapshotData.write(to: snapshotURL, options: .atomic)
        return snapshotURL
    }

    @discardableResult
    public func restoreResumeSnapshot(named name: String = "default") async throws -> ResumeDataSnapshot {
        let snapshotURL = snapshotFileURL(for: name)
        let snapshotData = try Data(contentsOf: snapshotURL)
        try await sessionStorage.restoreResumeData(from: snapshotData)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResumeDataSnapshot.self, from: snapshotData)
    }

    @discardableResult
    public func restoreLatestResumeSnapshot() async throws -> URL? {
        let snapshots = try persistedResumeSnapshots()
        guard let latest = snapshots.last else {
            return nil
        }

        let data = try Data(contentsOf: latest)
        try await sessionStorage.restoreResumeData(from: data)
        return latest
    }

    public func persistedResumeSnapshots() throws -> [URL] {
        try sortedFiles(in: snapshotsDirectoryURL(), pathExtension: "json")
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
        timeout: Duration,
        pollInterval: Duration
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

            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
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
                        try await Task.sleep(for: pollInterval)
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
        try FileManager.default.createDirectory(at: snapshotsDirectoryURL(), withIntermediateDirectories: true)
    }

    private func torrentFilesDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("TorrentFiles", isDirectory: true).standardizedFileURL
    }

    private func snapshotsDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("Snapshots", isDirectory: true).standardizedFileURL
    }

    private func snapshotFileURL(for name: String) -> URL {
        let sanitizedName = sanitizeFileStem(name.isEmpty ? "default" : name)
        return snapshotsDirectoryURL()
            .appendingPathComponent("\(sanitizedName).json")
            .standardizedFileURL
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
