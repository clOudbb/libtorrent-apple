import Foundation
import Testing
@testable import LibtorrentApple

@Suite(.serialized)
struct TorrentSessionTests {
    @Test
    func sessionConfigurationDefaultsToDualStackListenInterfaces() {
        #expect(SessionConfiguration.default.listenInterfaces == ["0.0.0.0:0", "[::]:0"])
    }

    @Test
    func torrentBackendInfoDecodingBackfillsHTTPSCapability() throws {
        let legacyJSON = """
        {"vendor":"libtorrent","libraryVersion":"2.0.12","bridgeVersion":"2.0.12","packageName":"LibtorrentApple"}
        """.data(using: .utf8)!
    
        let decodedLegacy = try JSONDecoder().decode(TorrentBackendInfo.self, from: legacyJSON)
        #expect(decodedLegacy.supportsHTTPSTrackers == false)
        #expect(decodedLegacy.supportsSessionRuntimeSettings == false)
    
        let current = LibtorrentApple.backendInfo
        _ = current.supportsHTTPSTrackers
        _ = current.supportsSessionRuntimeSettings
    }
    
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
        #expect([TorrentState.running, .idle, .paused].contains(added.state))
    
        let paused = try await session.pauseTorrent(id: added.id)
        #expect(paused.state == .paused)
    
        let resumed = try await session.resumeTorrent(id: added.id)
        #expect([TorrentState.running, .idle].contains(resumed.state))
    
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
    func sessionDiagnosticsExposeListenState() async throws {
        let session = TorrentSession()
        try await session.start()

        let diagnostics = try await session.sessionDiagnostics()

        #expect(BridgeRuntime.supportsListenStateDiagnostics)
        #expect(diagnostics.isListening != nil)
        #expect(diagnostics.listenPort != nil)
        #expect(diagnostics.sslListenPort != nil)

        await session.stop()
    }

    @Test
    func reopenNetworkSocketsUsesNativeBridgeFunction() async throws {
        let session = TorrentSession()
        try await session.start()

        let reopenedNatively = try await session.reopenNetworkSockets()

        #expect(BridgeRuntime.supportsNetworkSocketReopen)
        #expect(reopenedNatively)

        await session.stop()
    }

    @Test
    func networkRecoveryReannouncesEvenWhenSocketRecoveryThrows() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleRecoveryFallback-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("episode.torrent")

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "episode-04.mkv").write(to: torrentFileURL, options: .atomic)

        let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
        try await session.start()
        _ = try await session.addTorrent(from: .torrentFile(torrentFileURL, displayName: "Episode 04"))

        let reannounceCount = try await session.recoverNetworkAndReannounce(
            nativeEventName: "session_network_path_changed",
            triggerDescription: "Network path changed",
            recovery: {
                throw LibtorrentAppleError.nativeOperationFailed(-77, "Injected recovery failure")
            }
        )

        #expect(reannounceCount == 1)

        await session.stop()
    }

    @Test
    func binaryBackendsReportHTTPSTrackerSupport() {
        let packageMode = ProcessInfo.processInfo.environment["LIBTORRENT_APPLE_PACKAGE_MODE"]

        if packageMode == "local-binary" || packageMode == "remote-binary" {
            #expect(LibtorrentApple.backendSupportsHTTPSTrackers)
            #expect(LibtorrentApple.backendInfo.supportsHTTPSTrackers)
        }
    }

    @Test
    func httpsTrackerReannounceDoesNotFailWithUnsupportedURLProtocolWhenBackendEnabled() async throws {
        guard LibtorrentApple.backendSupportsHTTPSTrackers else {
            return
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleHTTPSTrackers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
        try await session.start()

        guard try await waitForListeningSession(session, timeoutSeconds: 3) else {
            await session.stop()
            return
        }

        let trackerURL = "https://127.0.0.1:1/announce"
        let encodedTrackerURL = try #require(
            trackerURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        )
        let magnetURL = try #require(
            URL(string:
                "magnet:?xt=urn:btih:1234567890abcdef1234567890abcdef12345678&dn=HTTPS%20Tracker%20Test&tr=\(encodedTrackerURL)"
            )
        )

        let added = try await session.addTorrent(
            from: .magnetLink(magnetURL, displayName: "HTTPS Tracker Test")
        )
        let handle = try #require(await session.handle(for: added.id))

        try await handle.forceReannounce(after: 0, ignoreMinimumInterval: true)

        let tracker = try await waitForTrackerFailure(on: handle, expectedURL: trackerURL, timeoutSeconds: 5)
        let trackerMessage = tracker.message?.lowercased() ?? ""

        #expect(tracker.url == trackerURL)
        #expect(tracker.failureCount > 0 || !trackerMessage.isEmpty)
        #expect(!trackerMessage.contains("unsupported_url_protocol"))
        #expect(!trackerMessage.contains("unsupported url protocol"))

        await session.stop()
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
    func torrentDownloaderSupportsEncodedTorrentAndManagedFiles() async throws {
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
        let managedTorrentFiles = try await downloader.managedTorrentFiles()
        let fetchedTorrent = try await downloader.fetchTorrent(from: managedTorrentFiles[0])

        #expect(status.name == "Episode 01")
        #expect(saveDirectory == defaultSaveDirectory)
        #expect(stats.torrentCount == 1)
        #expect((0...1).contains(stats.runningTorrentCount))
        #expect(managedTorrentFiles.count == 1)
        #expect(fetchedTorrent.data == encodedTorrent.data)
    }

    @Test
    func stoppedDownloaderConfigurationChangesMarkPersistentStateDirty() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleStoppedConfigDirty-\(UUID().uuidString)", isDirectory: true)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory, userAgent: "tests/original"),
            rootDirectory: rootDirectory
        )

        let initialManifestURL = try await downloader.savePersistentState()
        #expect(FileManager.default.fileExists(atPath: initialManifestURL.path))
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        var updatedConfiguration = await downloader.configuration
        updatedConfiguration.userAgent = "tests/updated"
        updatedConfiguration.activeDownloadsLimit = 3
        try await downloader.applyConfiguration(updatedConfiguration)

        #expect(await downloader.hasPendingPersistentStateChanges())

        let flushedURL = try await downloader.flushScheduledPersistentStateSave()
        #expect(flushedURL != nil)
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        let manifestData = try Data(contentsOf: try #require(flushedURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)

        #expect(manifest.configuration.userAgent == "tests/updated")
        #expect(manifest.configuration.activeDownloadsLimit == 3)
    }

    @Test
    func deferredConfigurationMarksPersistentStateDirtyBeforeApply() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleDeferredConfigDirty-\(UUID().uuidString)", isDirectory: true)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory, userAgent: "tests/original"),
            rootDirectory: rootDirectory
        )

        _ = try await downloader.savePersistentState()
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        var updatedConfiguration = await downloader.configuration
        updatedConfiguration.userAgent = "tests/deferred"
        updatedConfiguration.activeDownloadsLimit = 7
        await downloader.scheduleConfigurationApply(updatedConfiguration, debounceInterval: 60)

        #expect(await downloader.hasPendingPersistentStateChanges())
        #expect(await downloader.configuration.userAgent == "tests/original")

        let flushedURL = try await downloader.flushScheduledPersistentStateSave()
        #expect(flushedURL != nil)
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        let manifestData = try Data(contentsOf: try #require(flushedURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)

        #expect(manifest.configuration.userAgent == "tests/deferred")
        #expect(manifest.configuration.activeDownloadsLimit == 7)
    }

    @Test
    func deferredRuntimePatchMarksPersistentStateDirtyBeforeApply() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleDeferredRuntimeDirty-\(UUID().uuidString)", isDirectory: true)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory),
            rootDirectory: rootDirectory
        )
        try await downloader.start()

        _ = try await downloader.savePersistentState()
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        await downloader.scheduleRuntimePatch(
            SessionRuntimePatch(connectionsLimit: 222),
            debounceInterval: 60
        )

        #expect(await downloader.hasPendingPersistentStateChanges())

        let flushedURL = try await downloader.flushScheduledPersistentStateSave()
        #expect(flushedURL != nil)
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        let manifestData = try Data(contentsOf: try #require(flushedURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)

        #expect(manifest.configuration.connectionsLimit == 222)
        await downloader.stop()
    }

    @Test
    func trailingRateLimitsMarkPersistentStateDirtyBeforeThrottleFlush() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleTrailingRateDirty-\(UUID().uuidString)", isDirectory: true)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory),
            rootDirectory: rootDirectory
        )
        try await downloader.start()

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 32 * 1024,
            downloadBytesPerSecond: 256 * 1024,
            throttleInterval: 60
        )
        _ = try await downloader.savePersistentState()
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 60
        )

        #expect(await downloader.hasPendingPersistentStateChanges())

        let flushedURL = try await downloader.flushScheduledPersistentStateSave()
        #expect(flushedURL != nil)
        #expect(!(await downloader.hasPendingPersistentStateChanges()))

        let manifestData = try Data(contentsOf: try #require(flushedURL))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)

        #expect(manifest.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(manifest.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)
        await downloader.stop()
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
        let saveDirectoryBeforeCompletion = try await handle.downloadDirectory()
        let saveDirectory = try await waitForDownloadDirectory(
            on: handle,
            expectedDirectory: movedDirectory,
            timeoutSeconds: 2
        )
    
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
        #expect(saveDirectoryBeforeCompletion == rootDirectory)
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
        appliedConfiguration.activeDownloadsLimit = -1
        appliedConfiguration.activeSeedsLimit = -1
        appliedConfiguration.activeTorrentLimit = -1
        appliedConfiguration.connectionSpeed = 40
        appliedConfiguration.torrentConnectBoost = 80
        appliedConfiguration.maxOutgoingRequestQueueSize = 600
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
        #expect(await session.configuration.activeDownloadsLimit == appliedConfiguration.activeDownloadsLimit)
        #expect(await session.configuration.activeSeedsLimit == appliedConfiguration.activeSeedsLimit)
        #expect(await session.configuration.activeTorrentLimit == appliedConfiguration.activeTorrentLimit)
        #expect(await session.configuration.connectionSpeed == appliedConfiguration.connectionSpeed)
        #expect(await session.configuration.torrentConnectBoost == appliedConfiguration.torrentConnectBoost)
        #expect(await session.configuration.maxOutgoingRequestQueueSize == appliedConfiguration.maxOutgoingRequestQueueSize)
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
    func runtimePatchSettersApplyWithoutFullConfiguration() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleRuntimePatch-\(UUID().uuidString)", isDirectory: true)

        var initialConfiguration = SessionConfiguration(downloadDirectory: rootDirectory)
        initialConfiguration.enableDistributedHashTable = true
        initialConfiguration.enableUPnP = false
        initialConfiguration.enableNATPMP = false

        let session = TorrentSession(configuration: initialConfiguration)
        try await session.start()

        try await session.setRateLimits(
            uploadBytesPerSecond: 128 * 1024,
            downloadBytesPerSecond: 1024 * 1024
        )
        try await session.setConnectionLimits(
            globalConnections: 420,
            connectionSpeed: 35,
            torrentConnectBoost: 70,
            allowMultipleConnectionsPerIP: true
        )
        try await session.setActiveLimits(
            downloads: -1,
            seeds: -1,
            checking: 1,
            distributedHashTable: -1,
            trackers: -1,
            localPeerDiscovery: -1,
            torrents: -1
        )
        try await session.setRateLimitOptions(includeIPOverhead: true)
        try await session.setTransportBehavior(.tcpOnly)

        let configuration = await session.configuration
        #expect(configuration.uploadRateLimitBytesPerSecond == 128 * 1024)
        #expect(configuration.downloadRateLimitBytesPerSecond == 1024 * 1024)
        #expect(configuration.connectionsLimit == 420)
        #expect(configuration.connectionSpeed == 35)
        #expect(configuration.torrentConnectBoost == 70)
        #expect(configuration.activeDownloadsLimit == -1)
        #expect(configuration.activeSeedsLimit == -1)
        #expect(configuration.activeCheckingLimit == 1)
        #expect(configuration.includeIPOverheadInRateLimit == true)
        #expect(configuration.allowMultipleConnectionsPerIP == true)
        #expect(configuration.enableOutgoingTCP == true)
        #expect(configuration.enableIncomingTCP == true)
        #expect(configuration.enableOutgoingUTP == false)
        #expect(configuration.enableIncomingUTP == false)
        #expect(configuration.mixedModeAlgorithm == .preferTCP)
        #expect(configuration.enableDistributedHashTable == initialConfiguration.enableDistributedHashTable)
        #expect(configuration.enableUPnP == initialConfiguration.enableUPnP)
        #expect(configuration.enableNATPMP == initialConfiguration.enableNATPMP)
    }

    @Test
    func runtimePatchRebasesPendingFullConfiguration() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let session = TorrentSession()
        try await session.start()

        var pendingConfiguration = await session.configuration
        pendingConfiguration.connectionsLimit = 321
        await session.scheduleConfigurationApply(pendingConfiguration, debounceInterval: 60)

        try await session.setRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024
        )

        let applied = await session.flushDeferredConfigurationApply()
        #expect(applied)
        #expect(await session.configuration.connectionsLimit == 321)
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(await session.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)
    }

    @Test
    func scheduledRateLimitsApplyImmediatelyThenCoalesceTrailingValue() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let session = TorrentSession()
        try await session.start()

        await session.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.05
        )
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(await session.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)

        await session.scheduleRateLimits(
            uploadBytesPerSecond: 256 * 1024,
            downloadBytesPerSecond: 2 * 1024 * 1024,
            throttleInterval: 0.05
        )
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)

        try await Task.sleep(nanoseconds: 90_000_000)
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 256 * 1024)
        #expect(await session.configuration.downloadRateLimitBytesPerSecond == 2 * 1024 * 1024)
    }

    @Test
    func downloaderDeferredConfigurationFailureDoesNotCachePendingConfiguration() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleDownloaderConfigRollback-\(UUID().uuidString)", isDirectory: true)
        let downloader = TorrentDownloader(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
        try await downloader.start()

        let originalDirectory = await downloader.configuration.downloadDirectory
        var invalidRuntimeConfiguration = await downloader.configuration
        invalidRuntimeConfiguration.downloadDirectory = rootDirectory
            .appendingPathComponent("RuntimeDirectoryChange", isDirectory: true)

        await downloader.scheduleConfigurationApply(invalidRuntimeConfiguration, debounceInterval: 60)
        #expect(await downloader.configuration.downloadDirectory == originalDirectory)

        let applied = await downloader.flushDeferredConfigurationApply()
        #expect(!applied)
        #expect(await downloader.configuration.downloadDirectory == originalDirectory)
    }

    @Test
    func downloaderScheduledRateLimitsSynchronizeCachedConfigurationAfterTrailingApply() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let downloader = TorrentDownloader()
        try await downloader.start()

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.05
        )
        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 128 * 1024,
            downloadBytesPerSecond: 1024 * 1024,
            throttleInterval: 0.05
        )

        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 128 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 1024 * 1024)
    }

    @Test
    func downloaderScheduledRateLimitsDoNotFlushBeforeSessionThrottleWindow() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let downloader = TorrentDownloader()
        try await downloader.start()

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.2
        )
        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 128 * 1024,
            downloadBytesPerSecond: 1024 * 1024,
            throttleInterval: 0.02
        )

        try await Task.sleep(nanoseconds: 90_000_000)
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)

        _ = await downloader.flushScheduledRateLimits()
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 128 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 1024 * 1024)
    }

    @Test
    func downloaderScheduledRateLimitsDoNotLeaveConfigurationStalePastSessionThrottleWindow() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let downloader = TorrentDownloader()
        try await downloader.start()

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.05
        )
        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 128 * 1024,
            downloadBytesPerSecond: 1024 * 1024,
            throttleInterval: 0.2
        )

        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 128 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 1024 * 1024)
    }

    @Test
    func downloaderManualRateLimitFlushCancelsStaleSyncTask() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let downloader = TorrentDownloader()
        try await downloader.start()

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 32 * 1024,
            downloadBytesPerSecond: 256 * 1024,
            throttleInterval: 0.08
        )
        _ = await downloader.flushScheduledRateLimits()

        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.2
        )
        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 128 * 1024,
            downloadBytesPerSecond: 1024 * 1024,
            throttleInterval: 0.2
        )

        try await Task.sleep(nanoseconds: 110_000_000)
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)

        _ = await downloader.flushScheduledRateLimits()
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 128 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 1024 * 1024)
    }

    @Test
    func downloaderKeepsSeparateSyncsForDifferentDeferredOperations() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let downloader = TorrentDownloader()
        try await downloader.start()

        var pendingConfiguration = await downloader.configuration
        pendingConfiguration.connectionsLimit = 321

        await downloader.scheduleConfigurationApply(pendingConfiguration, debounceInterval: 0.12)
        await downloader.scheduleRateLimits(
            uploadBytesPerSecond: 96 * 1024,
            downloadBytesPerSecond: 768 * 1024,
            throttleInterval: 0.02
        )

        try await Task.sleep(nanoseconds: 70_000_000)
        #expect(await downloader.configuration.uploadRateLimitBytesPerSecond == 96 * 1024)
        #expect(await downloader.configuration.downloadRateLimitBytesPerSecond == 768 * 1024)

        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(await downloader.configuration.connectionsLimit == 321)
    }

    @Test
    func flushedScheduledRateLimitTaskDoesNotApplyNewerWindowEarly() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let session = TorrentSession()
        try await session.start()

        await session.scheduleRateLimits(
            uploadBytesPerSecond: 32 * 1024,
            downloadBytesPerSecond: 256 * 1024,
            throttleInterval: 0.08
        )
        _ = await session.flushScheduledRateLimits()

        await session.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.2
        )
        await session.scheduleRateLimits(
            uploadBytesPerSecond: 128 * 1024,
            downloadBytesPerSecond: 1024 * 1024,
            throttleInterval: 0.2
        )

        try await Task.sleep(nanoseconds: 110_000_000)
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(await session.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)

        _ = await session.flushScheduledRateLimits()
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 128 * 1024)
        #expect(await session.configuration.downloadRateLimitBytesPerSecond == 1024 * 1024)
    }

    @Test
    func scheduledRateLimitsMergeTrailingSparseValues() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let session = TorrentSession()
        try await session.start()

        await session.scheduleRateLimits(
            uploadBytesPerSecond: 32 * 1024,
            downloadBytesPerSecond: 256 * 1024,
            throttleInterval: 0.2
        )
        await session.scheduleRateLimits(
            uploadBytesPerSecond: 64 * 1024,
            throttleInterval: 0.2
        )
        await session.scheduleRateLimits(
            downloadBytesPerSecond: 512 * 1024,
            throttleInterval: 0.2
        )

        _ = await session.flushScheduledRateLimits()
        #expect(await session.configuration.uploadRateLimitBytesPerSecond == 64 * 1024)
        #expect(await session.configuration.downloadRateLimitBytesPerSecond == 512 * 1024)
    }

    @Test
    func flushedDeferredRuntimePatchTaskDoesNotApplyNewerWindowEarly() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let session = TorrentSession()
        try await session.start()

        await session.scheduleRuntimePatch(
            SessionRuntimePatch(connectionsLimit: 111),
            debounceInterval: 0.08
        )
        _ = await session.flushDeferredRuntimePatch()

        await session.scheduleRuntimePatch(
            SessionRuntimePatch(connectionsLimit: 222),
            debounceInterval: 0.2
        )
        await session.scheduleRuntimePatch(
            SessionRuntimePatch(connectionsLimit: 333),
            debounceInterval: 0.2
        )

        try await Task.sleep(nanoseconds: 110_000_000)
        #expect(await session.configuration.connectionsLimit == 111)

        _ = await session.flushDeferredRuntimePatch()
        #expect(await session.configuration.connectionsLimit == 333)
    }

    @Test
    func scheduledRuntimePatchMergesSparseValuesBeforeDebounce() async throws {
        guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let session = TorrentSession()
        try await session.start()

        await session.scheduleRuntimePatch(
            SessionRuntimePatch(connectionsLimit: 111),
            debounceInterval: 0.2
        )
        await session.scheduleRuntimePatch(
            SessionRuntimePatch(connectionSpeed: 22),
            debounceInterval: 0.2
        )

        _ = await session.flushDeferredRuntimePatch()
        #expect(await session.configuration.connectionsLimit == 111)
        #expect(await session.configuration.connectionSpeed == 22)
    }

    @Test
    func downloaderTransportFallbackMergesPendingConfiguration() async throws {
        guard !LibtorrentApple.backendSupportsSessionRuntimeSettings else {
            return
        }

        let downloader = TorrentDownloader()
        try await downloader.start()

        var pending = await downloader.configuration
        pending.connectionsLimit = 321
        await downloader.scheduleConfigurationApply(pending, debounceInterval: 0.2)
        await downloader.scheduleTransportBehaviorApply(.utpOnly, debounceInterval: 0.2)

        let applied = await downloader.flushDeferredConfigurationApply()
        #expect(applied)
        #expect(await downloader.configuration.connectionsLimit == 321)
        #expect(await downloader.configuration.enableOutgoingTCP == false)
        #expect(await downloader.configuration.enableIncomingTCP == false)
        #expect(await downloader.configuration.enableOutgoingUTP == true)
        #expect(await downloader.configuration.enableIncomingUTP == true)
        #expect(await downloader.configuration.mixedModeAlgorithm == .peerProportional)
    }
    
    @Test
    func sessionProfilesApplyExpectedDefaults() async throws {
        #expect(SessionProfile.allCases == [
            .baseline,
            .animekoParityV1,
            .animekoParityV2,
            .qBittorrentParityV1,
            .transmissionParityV1,
        ])
        #expect(SessionProfile.throughputReferenceProfiles == [
            .animekoParityV2,
            .qBittorrentParityV1,
            .transmissionParityV1,
        ])

        var v1 = SessionConfiguration()
        v1.applyProfile(.animekoParityV1)
        #expect(v1.connectionsLimit == 200)
        #expect(v1.dhtBootstrapNodes == SessionProfile.animekoParityV1.defaultDHTBootstrapNodes)
        #expect(v1.trackerPresetURLs.count == SessionProfile.animekoParityV1.defaultTrackerPreset.count)
    
        var v2 = SessionConfiguration()
        v2.applyProfile(.animekoParityV2)
        #expect(v2.connectionsLimit == 1000)
        #expect(v2.announceToAllTrackers == true)
        #expect(v2.announceToAllTiers == true)
        #expect(v2.peerTurnover == 8)
        #expect(v2.peerTurnoverCutoff == 85)
        #expect(v2.peerTurnoverInterval == 120)
        #expect(v2.mixedModeAlgorithm == .preferTCP)
        #expect(v2.chokingAlgorithm == .rateBased)
        #expect(v2.seedChokingAlgorithm == .fastestUpload)
        #expect(v2.maxOutgoingRequestQueueSize == 2000)
        #expect(v2.maxAllowedIncomingRequestQueueSize == 2000)
        #expect(v2.wholePiecesThreshold == 20)
        #expect(v2.enablePieceExtentAffinity == true)
        #expect(v2.suggestMode == .suggestReadCache)
        #expect(v2.aioThreads == 12)
        #expect(v2.checkingMemoryUsage == 32)
        #expect(v2.filePoolSize == 1000)
        #expect(v2.maxConcurrentHTTPAnnounces == 100)
        #expect(v2.stopTrackerTimeout == 5)
        #expect(v2.activeTorrentLimit == -1)
        #expect(v2.maxQueuedDiskBytes == 16 * 1024 * 1024)
        #expect(v2.sendBufferLowWatermarkBytes == 64 * 1024)
        #expect(v2.sendBufferWatermarkBytes == 2 * 1024 * 1024)
        #expect(v2.sendBufferWatermarkFactorPercent == 150)
        #expect(v2.enableUPnP)
        #expect(v2.enableNATPMP)
    
        var qb = SessionConfiguration()
        qb.applyProfile(.qBittorrentParityV1)
        #expect(qb.connectionsLimit == 500)
        #expect(qb.announceToAllTrackers == false)
        #expect(qb.announceToAllTiers == true)
        #expect(qb.peerTurnover == 4)
        #expect(qb.peerTurnoverCutoff == 90)
        #expect(qb.peerTurnoverInterval == 300)
        #expect(qb.connectionSpeed == 30)
        #expect(qb.torrentConnectBoost == 50)
        #expect(qb.mixedModeAlgorithm == .preferTCP)
        #expect(qb.chokingAlgorithm == .fixedSlots)
        #expect(qb.seedChokingAlgorithm == .fastestUpload)
        #expect(qb.maxOutgoingRequestQueueSize == 500)
        #expect(qb.maxAllowedIncomingRequestQueueSize == 2000)
        #expect(qb.wholePiecesThreshold == 20)
        #expect(qb.enablePieceExtentAffinity == false)
        #expect(qb.suggestMode == .noPieceSuggestions)
        #expect(qb.aioThreads == 10)
        #expect(qb.checkingMemoryUsage == 32)
        #expect(qb.filePoolSize == 5000)
        #expect(qb.maxConcurrentHTTPAnnounces == 50)
        #expect(qb.stopTrackerTimeout == 5)
        #expect(qb.includeIPOverheadInRateLimit == false)
        #expect(qb.allowMultipleConnectionsPerIP == false)
        #expect(qb.validateHTTPSTrackers == true)
        #expect(qb.enableSSRFMitigation == true)
        #expect(qb.enableOutgoingTCP == true)
        #expect(qb.enableIncomingTCP == true)
        #expect(qb.enableOutgoingUTP == true)
        #expect(qb.enableIncomingUTP == true)
        #expect(qb.sendBufferLowWatermarkBytes == 10 * 1024)
        #expect(qb.sendBufferWatermarkBytes == 500 * 1024)
        #expect(qb.sendBufferWatermarkFactorPercent == 50)
        #expect(qb.trackerPresetURLs.isEmpty)

        var transmission = SessionConfiguration()
        transmission.applyProfile(.transmissionParityV1)
        #expect(transmission.connectionsLimit == 200)
        #expect(transmission.activeDownloadsLimit == 5)
        #expect(transmission.activeSeedsLimit == -1)
        #expect(transmission.activeCheckingLimit == 1)
        #expect(transmission.announceToAllTrackers == false)
        #expect(transmission.announceToAllTiers == true)
        #expect(transmission.peerTurnover == 4)
        #expect(transmission.peerTurnoverCutoff == 90)
        #expect(transmission.peerTurnoverInterval == 300)
        #expect(transmission.connectionSpeed == 30)
        #expect(transmission.torrentConnectBoost == 30)
        #expect(transmission.mixedModeAlgorithm == .peerProportional)
        #expect(transmission.chokingAlgorithm == .fixedSlots)
        #expect(transmission.seedChokingAlgorithm == .fastestUpload)
        #expect(transmission.maxOutgoingRequestQueueSize == 500)
        #expect(transmission.maxAllowedIncomingRequestQueueSize == 2000)
        #expect(transmission.wholePiecesThreshold == 20)
        #expect(transmission.enablePieceExtentAffinity == false)
        #expect(transmission.suggestMode == .noPieceSuggestions)
        #expect(transmission.aioThreads == 8)
        #expect(transmission.checkingMemoryUsage == 32)
        #expect(transmission.filePoolSize == 500)
        #expect(transmission.maxConcurrentHTTPAnnounces == 50)
        #expect(transmission.stopTrackerTimeout == 5)
        #expect(transmission.maxQueuedDiskBytes == 8 * 1024 * 1024)
        #expect(transmission.sendBufferLowWatermarkBytes == 10 * 1024)
        #expect(transmission.sendBufferWatermarkBytes == 500 * 1024)
        #expect(transmission.sendBufferWatermarkFactorPercent == 50)
        #expect(transmission.enableUPnP)
        #expect(transmission.enableNATPMP)
        #expect(transmission.trackerPresetURLs.isEmpty)
    }

    @Test
    func transportBehaviorControlsWork() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleTransportBehavior-\(UUID().uuidString)", isDirectory: true)
    
        let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
        try await session.start()
    
        try await session.setTransportBehavior(.tcpOnly)
        #expect(await session.configuration.enableOutgoingTCP == true)
        #expect(await session.configuration.enableIncomingTCP == true)
        #expect(await session.configuration.enableOutgoingUTP == false)
        #expect(await session.configuration.enableIncomingUTP == false)
        #expect(await session.configuration.mixedModeAlgorithm == .preferTCP)
    
        await session.scheduleTransportBehaviorApply(.utpOnly, debounceInterval: 0.01)
        let applied =
            if LibtorrentApple.backendSupportsSessionRuntimeSettings {
                await session.flushDeferredRuntimePatch()
            } else {
                await session.flushDeferredConfigurationApply()
            }
        #expect(applied)
        #expect(await session.configuration.enableOutgoingTCP == false)
        #expect(await session.configuration.enableIncomingTCP == false)
        #expect(await session.configuration.enableOutgoingUTP == true)
        #expect(await session.configuration.enableIncomingUTP == true)
        #expect(await session.configuration.mixedModeAlgorithm == .peerProportional)
    
        await session.stop()
    }
    
    @Test
    func throughputOptimizerBoostAndRestoreWork() async throws {
        let packageMode = ProcessInfo.processInfo.environment["LIBTORRENT_APPLE_PACKAGE_MODE"]
        if packageMode == "local-binary" || packageMode == "remote-binary" {
            // Known issue: on Apple real-binary builds, this test reliably drives session
            // teardown through libtorrent's default mmap disk backend and can crash in
            // mmap_disk_io::remove_torrent() during session_proxy destruction. We are
            // intentionally not changing the default disk backend semantics or carrying
            // a downstream libtorrent patch in this repository, so keep this stress path
            // suspended for binary-backed package modes until upstream fixes teardown.
            return
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleThroughputOptimizer-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("optimizer.torrent")
    
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "optimizer.mkv").write(to: torrentFileURL, options: .atomic)
    
        let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
        try await session.start()
        _ = try await session.addTorrent(from: .torrentFile(torrentFileURL, displayName: "Optimizer"))
    
        var baseline = await session.configuration
        baseline.connectionSpeed = 5
        baseline.torrentConnectBoost = 10
        baseline.maxOutgoingRequestQueueSize = 100
        baseline.maxAllowedIncomingRequestQueueSize = 60
        try await session.applyConfiguration(baseline)
    
        let policy = SessionThroughputOptimizerPolicy(
            sampleIntervalSeconds: 0.01,
            lowSpeedThresholdBytesPerSecond: .max,
            recoverySpeedThresholdBytesPerSecond: Int64.max,
            consecutiveLowSpeedWindowsForBoost: 1,
            consecutiveZeroSpeedWindowsForReannounce: 10,
            stableRecoveryWindowsForRestore: 100,
            cooldownSeconds: 0,
            boostedConnectionSpeed: 55,
            boostedTorrentConnectBoost: 90,
            boostedMaxOutgoingRequestQueueSize: 700,
            boostedMaxAllowedIncomingRequestQueueSize: 320,
            boostedPeerTurnover: 6,
            boostedPeerTurnoverCutoff: 86,
            boostedPeerTurnoverInterval: 90
        )
    
        await session.startThroughputOptimizer(policy: policy)
        try await Task.sleep(nanoseconds: 120_000_000)
    
        #expect(await session.isThroughputOptimizerEnabled())
        #expect(await session.configuration.connectionSpeed >= baseline.connectionSpeed)
        #expect(await session.configuration.torrentConnectBoost >= baseline.torrentConnectBoost)
        #expect(await session.configuration.maxOutgoingRequestQueueSize >= baseline.maxOutgoingRequestQueueSize)
        #expect(await session.configuration.maxAllowedIncomingRequestQueueSize >= baseline.maxAllowedIncomingRequestQueueSize)
    
        await session.stopThroughputOptimizer()
        #expect(!(await session.isThroughputOptimizerEnabled()))
        #expect(await session.configuration.connectionSpeed == baseline.connectionSpeed)
        #expect(await session.configuration.torrentConnectBoost == baseline.torrentConnectBoost)
        #expect(await session.configuration.maxOutgoingRequestQueueSize == baseline.maxOutgoingRequestQueueSize)
        #expect(await session.configuration.maxAllowedIncomingRequestQueueSize == baseline.maxAllowedIncomingRequestQueueSize)
    
        await session.stop()
    }
    
    @Test
    func deferredApplyAndBatchReannounceHooksWork() async throws {
        let packageMode = ProcessInfo.processInfo.environment["LIBTORRENT_APPLE_PACKAGE_MODE"]
        if packageMode == "local-binary" || packageMode == "remote-binary" {
            // Same known Apple real-binary teardown issue as above. This test exercises
            // configuration batching and reannounce hooks correctly, but its stop/destroy
            // tail still hits the current libtorrent mmap teardown crash on binary-backed
            // package modes.
            return
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleDeferredApply-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("episode.torrent")
    
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "episode-03.mkv").write(to: torrentFileURL, options: .atomic)
    
        let session = TorrentSession(configuration: SessionConfiguration(downloadDirectory: rootDirectory))
        try await session.start()
        _ = try await session.addTorrent(from: .torrentFile(torrentFileURL, displayName: "Episode 03"))
    
        var deferredConfiguration = await session.configuration
        deferredConfiguration.connectionSpeed = 45
        deferredConfiguration.announceToAllTiers = true
        await session.scheduleConfigurationApply(deferredConfiguration, debounceInterval: 0.01)
        try await Task.sleep(nanoseconds: 80_000_000)
    
        #expect(await session.configuration.connectionSpeed == 45)
        #expect(await session.configuration.announceToAllTiers == true)
    
        let networkReannounceCount = try await session.handleNetworkPathChanged()
        let wakeupReannounceCount = try await session.handleSystemWakeupDetected()
    
        #expect(networkReannounceCount == 1)
        #expect(wakeupReannounceCount == 1)
    
        await session.stop()
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
        #expect(firstStats.map { (0...1).contains($0.runningTorrentCount) } == true)
        #expect(deletedURL == localFileURL)
        #expect(!FileManager.default.fileExists(atPath: deletedURL.path))
        #expect(pieceSnapshot?.pieces.count == 1)
    }

    @Test
    func downloaderPersistentStateRoundTripRestoresTorrent() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentApplePersistentState-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("persistent.torrent")

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "persistent.mkv").write(to: torrentFileURL, options: .atomic)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory, userAgent: "tests/persistent"),
            rootDirectory: rootDirectory
        )
        try await downloader.start()

        let handle = try await downloader.addTorrent(
            from: .torrentFile(torrentFileURL, displayName: "Persistent")
        )
        _ = try await handle.pause()

        let manifestURL = try await downloader.savePersistentState()
        let savedStatus = try await handle.status()
        let persistentResumeURL = persistentStateDirectoryURL(for: rootDirectory)
            .appendingPathComponent("ResumeData/\(savedStatus.id.rawValue).resume")
        let persistentTorrentURL = persistentStateDirectoryURL(for: rootDirectory)
            .appendingPathComponent("TorrentFiles/\(savedStatus.id.rawValue).torrent")

        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: persistentResumeURL.path))
        #expect(FileManager.default.fileExists(atPath: persistentTorrentURL.path))

        await downloader.stop()

        let restoredDownloader = TorrentDownloader(rootDirectory: rootDirectory)
        let report = try await restoredDownloader.restorePersistentState()

        #expect(report.entries.count == 1)
        #expect(report.restoredCount == 1)
        #expect(report.failedCount == 0)

        try await restoredDownloader.start()
        let restoredStatuses = await restoredDownloader.torrentStatuses()

        #expect(restoredStatuses.count == 1)
        #expect(restoredStatuses[0].name == "Persistent")
        #expect(restoredStatuses[0].state == .paused)
        #expect(await restoredDownloader.configuration.userAgent == "tests/persistent")
    }

    @Test
    func downloaderPersistentStateFallsBackToTorrentFileWhenResumeDataIsMissing() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentApplePersistentFallback-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("fallback.torrent")

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "fallback.mkv").write(to: torrentFileURL, options: .atomic)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory),
            rootDirectory: rootDirectory
        )
        try await downloader.start()

        let handle = try await downloader.addTorrent(
            from: .torrentFile(torrentFileURL, displayName: "Fallback")
        )
        let status = try await handle.status()
        _ = try await downloader.savePersistentState()
        await downloader.stop()

        let persistentResumeURL = persistentStateDirectoryURL(for: rootDirectory)
            .appendingPathComponent("ResumeData/\(status.id.rawValue).resume")
        try FileManager.default.removeItem(at: persistentResumeURL)

        let restoredDownloader = TorrentDownloader(rootDirectory: rootDirectory)
        let report = try await restoredDownloader.restorePersistentState()

        #expect(report.entries.count == 1)
        #expect(report.restoredCount == 0)
        #expect(report.degradedCount == 1)
        #expect(report.failedCount == 0)

        try await restoredDownloader.start()
        #expect((await restoredDownloader.torrentStatuses()).count == 1)
    }

    @Test
    func downloaderPersistentStateReturnsFailureWhenAllRestoreInputsAreMissing() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentApplePersistentMissing-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("missing.torrent")

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "missing.mkv").write(to: torrentFileURL, options: .atomic)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory),
            rootDirectory: rootDirectory
        )
        try await downloader.start()

        let handle = try await downloader.addTorrent(
            from: .torrentFile(torrentFileURL, displayName: "Missing")
        )
        let status = try await handle.status()
        _ = try await downloader.savePersistentState()
        await downloader.stop()

        let persistentDirectory = persistentStateDirectoryURL(for: rootDirectory)
        try FileManager.default.removeItem(at: persistentDirectory.appendingPathComponent("ResumeData/\(status.id.rawValue).resume"))
        try FileManager.default.removeItem(at: persistentDirectory.appendingPathComponent("TorrentFiles/\(status.id.rawValue).torrent"))
        try FileManager.default.removeItem(at: torrentFileURL)

        let restoredDownloader = TorrentDownloader(rootDirectory: rootDirectory)
        let report = try await restoredDownloader.restorePersistentState()

        #expect(report.entries.count == 1)
        #expect(report.failedCount == 1)
        #expect(report.restoredCount == 0)
        #expect(report.degradedCount == 0)

        try await restoredDownloader.start()
        #expect((await restoredDownloader.torrentStatuses()).isEmpty)
    }

    @Test
    func downloaderPersistentStateRejectsDuplicateTorrentIDsInManifest() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentApplePersistentDuplicateIDs-\(UUID().uuidString)", isDirectory: true)
        let persistentDirectory = persistentStateDirectoryURL(for: rootDirectory)
        let duplicateID = TorrentID(rawValue: "0123456789abcdef0123456789abcdef01234567")
        let addedAt = Date()

        try FileManager.default.createDirectory(at: persistentDirectory, withIntermediateDirectories: true)

        let manifest = PersistentStateManifest(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory),
            torrents: [
                PersistentStateManifestTorrent(
                    id: duplicateID,
                    name: "Duplicate A",
                    source: .magnetLink(
                        URL(string: "magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!,
                        displayName: "Duplicate A"
                    ),
                    downloadDirectory: rootDirectory,
                    desiredState: .paused,
                    addedAt: addedAt,
                    updatedAt: addedAt,
                    resumeDataFileName: nil,
                    torrentFileName: nil
                ),
                PersistentStateManifestTorrent(
                    id: duplicateID,
                    name: "Duplicate B",
                    source: .magnetLink(
                        URL(string: "magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")!,
                        displayName: "Duplicate B"
                    ),
                    downloadDirectory: rootDirectory,
                    desiredState: .running,
                    addedAt: addedAt,
                    updatedAt: addedAt,
                    resumeDataFileName: nil,
                    torrentFileName: nil
                ),
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: persistentDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let downloader = TorrentDownloader(rootDirectory: rootDirectory)

        do {
            _ = try await downloader.restorePersistentState()
            Issue.record("Expected duplicate torrent ids in manifest to throw.")
        } catch let error as LibtorrentAppleError {
            guard case let .resumeDataDecodingFailed(message) = error else {
                Issue.record("Expected resumeDataDecodingFailed, got \(error).")
                return
            }

            #expect(message.localizedCaseInsensitiveContains("duplicate torrent ids"))
            #expect(message.localizedCaseInsensitiveContains(duplicateID.rawValue))
        }
    }

    @Test
    func downloaderPersistentStateValidatesColdStartRestoreBeforeReportingSuccess() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentApplePersistentValidation-\(UUID().uuidString)", isDirectory: true)
        let torrentFileURL = rootDirectory.appendingPathComponent("validation.torrent")
        let invalidDownloadPath = rootDirectory.appendingPathComponent("not-a-directory")

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "validation.mkv").write(to: torrentFileURL, options: .atomic)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory.appendingPathComponent("Downloads", isDirectory: true)),
            rootDirectory: rootDirectory
        )
        try await downloader.start()
        _ = try await downloader.addTorrent(
            from: .torrentFile(torrentFileURL, displayName: "Validation"),
            options: AddTorrentOptions(downloadDirectory: rootDirectory.appendingPathComponent("Validated", isDirectory: true))
        )
        _ = try await downloader.savePersistentState()
        await downloader.stop()

        try Data("blocked".utf8).write(to: invalidDownloadPath, options: .atomic)
        let manifestURL = persistentStateDirectoryURL(for: rootDirectory).appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)
        manifest.torrents[0].downloadDirectory = invalidDownloadPath

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        let restoredDownloader = TorrentDownloader(rootDirectory: rootDirectory)
        let report = try await restoredDownloader.restorePersistentState()

        #expect(report.entries.count == 1)
        #expect(report.failedCount == 1)
        #expect(report.restoredCount == 0)
        #expect(report.degradedCount == 0)

        try await restoredDownloader.start()
        #expect((await restoredDownloader.torrentStatuses()).isEmpty)
    }

    @Test
    func coldStartBestEffortRestoreKeepsHealthyTorrentsWhenOneFails() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibtorrentAppleColdStartBestEffort-\(UUID().uuidString)", isDirectory: true)
        let goodTorrentURL = rootDirectory.appendingPathComponent("good.torrent")
        let badTorrentURL = rootDirectory.appendingPathComponent("bad.torrent")
        let goodDownloadDirectory = rootDirectory.appendingPathComponent("GoodDownloads", isDirectory: true)
        let blockedDownloadPath = rootDirectory.appendingPathComponent("BlockedDownloads")

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try makeEncodedTorrentData(fileName: "good.mkv").write(to: goodTorrentURL, options: .atomic)
        try makeEncodedTorrentData(fileName: "bad.mkv").write(to: badTorrentURL, options: .atomic)

        let downloader = TorrentDownloader(
            configuration: SessionConfiguration(downloadDirectory: rootDirectory),
            rootDirectory: rootDirectory
        )
        try await downloader.start()
        _ = try await downloader.addTorrent(
            from: .torrentFile(goodTorrentURL, displayName: "Good"),
            options: AddTorrentOptions(downloadDirectory: goodDownloadDirectory)
        )
        _ = try await downloader.addTorrent(
            from: .torrentFile(badTorrentURL, displayName: "Bad"),
            options: AddTorrentOptions(downloadDirectory: rootDirectory.appendingPathComponent("BadDownloads", isDirectory: true))
        )
        let manifestURL = try await downloader.savePersistentState()
        await downloader.stop()

        try Data("blocked".utf8).write(to: blockedDownloadPath, options: .atomic)
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var manifest = try decoder.decode(PersistentStateManifest.self, from: manifestData)
        #expect(manifest.torrents.count == 2)
        manifest.torrents[1].downloadDirectory = blockedDownloadPath

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        let restoredDownloader = TorrentDownloader(rootDirectory: rootDirectory)
        let report = try await restoredDownloader.restorePersistentState()
        try await restoredDownloader.start()

        let statuses = await restoredDownloader.torrentStatuses()
        #expect(report.entries.count == 2)
        #expect(report.failedCount == 1)
        #expect(report.restoredCount + report.degradedCount == 1)
        #expect(statuses.count == 1)
        #expect(statuses[0].downloadDirectory == goodDownloadDirectory)
    }
    
    private func makeEncodedTorrentData(fileName: String, length: Int = 16_384) -> Data {
        let pieces = Data(repeating: 0x31, count: 20)
        let prefix = "d8:announce14:http://tracker4:infod6:lengthi\(length)e4:name\(fileName.utf8.count):\(fileName)12:piece lengthi16384e6:pieces20:"
    
        var data = Data(prefix.utf8)
        data.append(pieces)
        data.append(Data("ee".utf8))
        return data
    }

    private func waitForTrackerFailure(
        on handle: TorrentHandle,
        expectedURL: String,
        timeoutSeconds: TimeInterval
    ) async throws -> TorrentTracker {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let trackers = try await handle.trackers()

            if let tracker = trackers.first(where: { tracker in
                tracker.url == expectedURL && (tracker.failureCount > 0 || !(tracker.message ?? "").isEmpty)
            }) {
                return tracker
            }

            try await Task.sleep(nanoseconds: 200_000_000)
        }

        if let tracker = try await handle.trackers().first(where: { $0.url == expectedURL }) {
            return tracker
        }

        throw TrackerWaitError.timedOut
    }

    private func waitForListeningSession(
        _ session: TorrentSession,
        timeoutSeconds: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let diagnostics = try await session.sessionDiagnostics()
            if diagnostics.isListening == true {
                return true
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        return try await session.sessionDiagnostics().isListening == true
    }

    private func waitForDownloadDirectory(
        on handle: TorrentHandle,
        expectedDirectory: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let currentDirectory = try await handle.downloadDirectory()
            if currentDirectory == expectedDirectory {
                return currentDirectory
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        return try await handle.downloadDirectory()
    }

    private func persistentStateDirectoryURL(for rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("PersistentState", isDirectory: true)
    }
}

private enum TrackerWaitError: Error {
    case timedOut
}
