import Foundation
import Testing
@testable import LibtorrentApple

@Test
func torrentSessionLifecycleAndStatusFlow() async throws {
    let session = TorrentSession()

    try await session.start()
    #expect(await session.isRunning)

    let source = TorrentSource.magnetLink(
        URL(string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")!,
        displayName: "Ubuntu ISO"
    )

    let added = try await session.addTorrent(from: source)
    #expect(added.name == "Ubuntu ISO")
    #expect(added.state == .running)

    let paused = try await session.pauseTorrent(id: added.id)
    #expect(paused.state == .paused)

    let resumed = try await session.resumeTorrent(id: added.id)
    #expect(resumed.state == .running)

    let fetched = try await session.torrentStatus(for: added.id)
    #expect(fetched.id == added.id)
    #expect(fetched.metrics.peerListCount >= 0)
    #expect(fetched.metrics.seedListCount >= 0)
    if let peerTotal = fetched.metrics.peerTotalCount {
        #expect(peerTotal >= 0)
    }
    if let seedTotal = fetched.metrics.seedTotalCount {
        #expect(seedTotal >= 0)
    }

    try await session.removeTorrent(id: added.id)
    let all = await session.allTorrentStatuses()
    #expect(all.isEmpty)

    await session.stop()
    #expect(!(await session.isRunning))
}

@Test
func resumeDataRoundTripRestoresState() async throws {
    let source = TorrentSource.magnetLink(
        URL(string: "magnet:?xt=urn:btih:89abcdef0123456789abcdef0123456789abcdef")!,
        displayName: "Example Torrent"
    )

    let session = TorrentSession(configuration: SessionConfiguration(userAgent: "tests/1.0"))
    try await session.start()
    let added = try await session.addTorrent(from: source)
    _ = try await session.pauseTorrent(id: added.id)

    let exported = try await session.exportResumeData()

    let restoredSession = TorrentSession()
    try await restoredSession.restoreResumeData(from: exported)

    let statuses = await restoredSession.allTorrentStatuses()
    #expect(statuses.count == 1)
    #expect(statuses.first?.name == "Example Torrent")
    #expect(statuses.first?.state == .paused)
    #expect(await restoredSession.configuration.userAgent == "tests/1.0")
}

@Test
func nativeResumeDataExportReturnsBytes() async throws {
    let session = TorrentSession()
    try await session.start()

    let source = TorrentSource.magnetLink(
        URL(string: "magnet:?xt=urn:btih:fedcba9876543210fedcba9876543210fedcba98")!,
        displayName: "Native Resume Data"
    )

    let added = try await session.addTorrent(from: source)
    let exported = try await session.exportNativeResumeData(for: added.id)

    #expect(!exported.isEmpty)
}

@Test
func nativeResumeDataCanRestoreIntoNewSession() async throws {
    let source = TorrentSource.magnetLink(
        URL(string: "magnet:?xt=urn:btih:00112233445566778899aabbccddeeff00112233")!,
        displayName: "Native Restore"
    )

    let exportingSession = TorrentSession()
    try await exportingSession.start()
    let added = try await exportingSession.addTorrent(from: source)
    let exported = try await exportingSession.exportNativeResumeData(for: added.id)

    let restoringSession = TorrentSession()
    try await restoringSession.start()
    let restored = try await restoringSession.addTorrent(fromNativeResumeData: exported)
    let statuses = await restoringSession.allTorrentStatuses()

    #expect(!restored.id.rawValue.isEmpty)
    #expect(statuses.count == 1)
}

@Test
func invalidMagnetSourceThrows() async throws {
    let session = TorrentSession()
    try await session.start()

    let invalid = TorrentSource.magnetLink(URL(string: "https://example.com/not-a-magnet")!)

    await #expect(throws: LibtorrentAppleError.self) {
        _ = try await session.addTorrent(from: invalid)
    }
}

@Test
func torrentFileExportReturnsEncodedMetadata() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibtorrentAppleTests-\(UUID().uuidString)", isDirectory: true)
    let torrentFileURL = rootDirectory.appendingPathComponent("fixture.torrent")

    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    try makeEncodedTorrentData(fileName: "fixture.bin").write(to: torrentFileURL, options: .atomic)

    let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
    try await session.start()

    let status = try await session.addTorrent(
        from: .torrentFile(torrentFileURL, displayName: "Fixture")
    )
    let exported = try await session.exportTorrentFile(for: status.id)

    #expect(!exported.isEmpty)
    #expect(status.downloadDirectory == rootDirectory)
    #expect(await session.handle(for: status.id) != nil)
}

@Test
func torrentDownloaderSupportsEncodedTorrentAndSnapshots() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibtorrentAppleDownloaderTests-\(UUID().uuidString)", isDirectory: true)

    let downloader = TorrentDownloader(
        configuration: SessionConfiguration(userAgent: "tests/downloader"),
        rootDirectory: rootDirectory
    )

    try await downloader.start()

    let encodedTorrent = EncodedTorrentInfo(
        data: makeEncodedTorrentData(fileName: "episode-01.mkv"),
        suggestedName: "Episode 01"
    )

    let handle = try await downloader.addTorrent(
        from: encodedTorrent,
        options: AddTorrentOptions(displayName: "Episode 01")
    )

    let status = try await handle.status()
    let defaultSaveDirectory = await downloader.defaultSaveDirectory()
    let saveDirectory = try await downloader.saveDirectory(for: handle)
    let stats = await downloader.totalStats()
    let snapshotURL = try await downloader.persistResumeSnapshot()
    let persistedSnapshots = try await downloader.persistedResumeSnapshots()
    let managedTorrentFiles = try await downloader.managedTorrentFiles()
    let fetchedTorrent = try await downloader.fetchTorrent(from: managedTorrentFiles[0])

    #expect(status.name == "Episode 01")
    #expect(saveDirectory == defaultSaveDirectory)
    #expect(stats.torrentCount == 1)
    #expect(stats.runningTorrentCount == 1)
    #expect(persistedSnapshots.contains(snapshotURL))
    #expect(managedTorrentFiles.count == 1)
    #expect(fetchedTorrent.data == encodedTorrent.data)
}

@Test
func torrentHandleExposesFileAndPieceControls() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibtorrentAppleControls-\(UUID().uuidString)", isDirectory: true)
    let torrentFileURL = rootDirectory.appendingPathComponent("controls.torrent")
    let movedDirectory = rootDirectory.appendingPathComponent("Moved", isDirectory: true)

    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    try makeEncodedTorrentData(fileName: "episode-01.mkv").write(to: torrentFileURL, options: .atomic)

    let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
    try await session.start()

    let status = try await session.addTorrent(
        from: .torrentFile(torrentFileURL, displayName: "Controls")
    )
    let handle = try #require(await session.handle(for: status.id))

    let files = try await handle.files()
    let fileHandle = try await handle.fileHandle(at: 0)
    let trackers = try await handle.trackers()
    let peers = try await handle.peers()
    let pieces = try await handle.pieces()
    let piecePriorities = try await handle.piecePriorities()
    let controller = try await handle.downloadController()

    #expect(files.count == 1)
    #expect(files[0].index == 0)
    #expect(!files[0].path.isEmpty)
    #expect(files[0].sizeBytes > 0)
    #expect(try await fileHandle.file().index == 0)
    #expect(trackers.count == 1)
    #expect(!trackers[0].url.isEmpty)
    #expect(peers.count >= 0)
    #expect(pieces.count == 1)
    #expect(pieces[0].index == 0)
    #expect(piecePriorities.count == 1)

    _ = try await handle.setFilePriority(.doNotDownload, at: 0)
    try await handle.setSequentialDownload(true)
    try await handle.forceRecheck()
    try await handle.forceReannounce(after: 0, ignoreMinimumInterval: true)

    let moved = try await handle.moveStorage(to: movedDirectory, strategy: .replaceExisting)
    let saveDirectory = try await handle.downloadDirectory()

    try await handle.setPiecePriority(.top, at: 0)
    let updatedPiecePriorities = try await handle.piecePriorities()
    try await handle.setPieceDeadline(at: 0, milliseconds: 1_500)
    try await handle.resetPieceDeadline(at: 0)
    let replacedTrackers = try await handle.replaceTrackers([
        TorrentTrackerUpdate(url: "https://tracker-1.example/announce", tier: 0),
        TorrentTrackerUpdate(url: "https://tracker-2.example/announce", tier: 1),
    ])
    let batchAddedTrackers = try await handle.addTrackers(
        [
            TorrentTrackerUpdate(url: "https://tracker-2.example/announce", tier: 1),
            TorrentTrackerUpdate(url: "https://tracker-3.example/announce", tier: 2),
        ],
        forceReannounce: false
    )
    let addedTrackers = try await handle.addTracker(TorrentTrackerUpdate(url: "https://tracker-4.example/announce", tier: 3))
    let streamingSnapshot = try await controller.prepareForStreaming(
        fileIndex: 0,
        leadPieceCount: 1,
        includeOnlySelectedFile: true
    )

    #expect(moved == movedDirectory)
    #expect(saveDirectory == movedDirectory)
    #expect(updatedPiecePriorities == [.top])
    #expect(replacedTrackers.count == 2)
    #expect(batchAddedTrackers.count == 3)
    #expect(addedTrackers.count == 4)
    #expect(streamingSnapshot.pieces.count == 1)
    #expect(streamingSnapshot.pieces[0].priority == .top)
}

@Test
func runtimeApplyConfigurationAndSessionDiagnosticsWork() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibtorrentAppleApplyConfig-\(UUID().uuidString)", isDirectory: true)

    var initialConfiguration = SessionConfiguration(downloadDirectory: rootDirectory)
    initialConfiguration.peerFingerprint = "-OK0160-"
    initialConfiguration.dhtBootstrapNodes = ["router.bittorrent.com:6881", "dht.libtorrent.org:25401"]
    initialConfiguration.shareRatioLimit = 200

    let session = TorrentSession(configuration: initialConfiguration)
    try await session.start()

    let source = TorrentSource.magnetLink(
        URL(string: "magnet:?xt=urn:btih:1111222233334444555566667777888899990000")!,
        displayName: "Apply Config"
    )
    _ = try await session.addTorrent(from: source)

    var appliedConfiguration = initialConfiguration
    appliedConfiguration.uploadRateLimitBytesPerSecond = 256 * 1024
    appliedConfiguration.downloadRateLimitBytesPerSecond = 2 * 1024 * 1024
    appliedConfiguration.connectionsLimit = 300
    appliedConfiguration.activeTorrentLimit = 12
    appliedConfiguration.autoSequentialDownload = true
    appliedConfiguration.peerFingerprint = "-OK0161-"
    appliedConfiguration.shareRatioLimit = 300
    appliedConfiguration.peerBlockedCIDRs = ["10.0.0.0/8"]
    appliedConfiguration.peerAllowedCIDRs = ["10.10.0.0/16"]

    try await session.applyConfiguration(appliedConfiguration)
    let diagnostics = try await session.sessionDiagnostics()

    #expect(await session.configuration.uploadRateLimitBytesPerSecond == appliedConfiguration.uploadRateLimitBytesPerSecond)
    #expect(await session.configuration.downloadRateLimitBytesPerSecond == appliedConfiguration.downloadRateLimitBytesPerSecond)
    #expect(await session.configuration.connectionsLimit == appliedConfiguration.connectionsLimit)
    #expect(await session.configuration.activeTorrentLimit == appliedConfiguration.activeTorrentLimit)
    #expect(await session.configuration.autoSequentialDownload == appliedConfiguration.autoSequentialDownload)
    #expect(await session.configuration.peerFingerprint == appliedConfiguration.peerFingerprint)
    #expect(await session.configuration.shareRatioLimit == appliedConfiguration.shareRatioLimit)
    #expect(await session.configuration.peerBlockedCIDRs == appliedConfiguration.peerBlockedCIDRs)
    #expect(await session.configuration.peerAllowedCIDRs == appliedConfiguration.peerAllowedCIDRs)
    #expect(diagnostics.aggregateDownloadRateBytesPerSecond >= 0)
    #expect(diagnostics.aggregateUploadRateBytesPerSecond >= 0)
    #expect(diagnostics.totalConnections >= 0)
    #expect(diagnostics.totalPeers >= 0)
    #expect(diagnostics.totalSeeds >= 0)
}

@Test
func animekoParityProfileAppliesExpectedDefaults() async throws {
    var configuration = SessionConfiguration()
    configuration.connectionsLimit = 0
    configuration.dhtBootstrapNodes = []

    configuration.applyProfile(.animekoParityV1)

    #expect(configuration.connectionsLimit == 200)
    #expect(configuration.dhtBootstrapNodes == SessionProfile.animekoParityV1.defaultDHTBootstrapNodes)
    #expect(SessionProfile.animekoParityV1.defaultTrackerPreset.count == 20)
}

@Test
func downloaderStatsStreamAndFileDeletionWork() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LibtorrentAppleStreaming-\(UUID().uuidString)", isDirectory: true)
    let torrentFileURL = rootDirectory.appendingPathComponent("episode.torrent")

    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    try makeEncodedTorrentData(fileName: "episode-02.mkv").write(to: torrentFileURL, options: .atomic)

    let downloader = TorrentDownloader(
        configuration: SessionConfiguration(downloadDirectory: rootDirectory),
        rootDirectory: rootDirectory
    )
    try await downloader.start()

    let handle = try await downloader.addTorrent(
        from: .torrentFile(torrentFileURL, displayName: "Episode 02")
    )

    let statsStream = await downloader.statsUpdates(pollInterval: 0.05)
    var statsIterator = statsStream.makeAsyncIterator()
    let firstStats = await statsIterator.next()

    let fileHandle = try await handle.fileHandle(at: 0)
    let file = try await fileHandle.file()
    let saveDirectory = try await handle.downloadDirectory()
    let localFileURL = saveDirectory.appendingPathComponent(file.path)
    try FileManager.default.createDirectory(at: localFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("payload".utf8).write(to: localFileURL, options: .atomic)

    let deletedURL = try await fileHandle.deleteLocalData()
    let controller = try await handle.downloadController()
    let pieceStream = controller.updates(pollInterval: 0.05)
    var pieceIterator = pieceStream.makeAsyncIterator()
    let pieceSnapshot = try await pieceIterator.next()

    #expect(firstStats?.torrentCount == 1)
    #expect(firstStats?.runningTorrentCount == 1)
    #expect(deletedURL == localFileURL)
    #expect(!FileManager.default.fileExists(atPath: deletedURL.path))
    #expect(pieceSnapshot?.pieces.count == 1)
}

private func makeEncodedTorrentData(fileName: String, length: Int = 16_384) -> Data {
    let pieces = Data(repeating: 0x31, count: 20)
    let prefix = "d8:announce14:http://tracker4:infod6:lengthi\(length)e4:name\(fileName.utf8.count):\(fileName)12:piece lengthi16384e6:pieces20:"

    var data = Data(prefix.utf8)
    data.append(pieces)
    data.append(Data("ee".utf8))
    return data
}
