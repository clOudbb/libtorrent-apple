public enum SessionProfile: String, Sendable, Hashable, Codable {
    case baseline
    case animekoParityV1 = "animekoParity.v1"
    case animekoParityV2 = "animekoParity.v2"
    case qBittorrentParityV1 = "qBittorrentParity.v1"
    case beastV1 = "beast.v1"

    public var defaultConnectionsLimit: Int? {
        switch self {
        case .baseline:
            return nil
        case .animekoParityV1:
            return 200
        case .animekoParityV2:
            return 1000
        case .qBittorrentParityV1:
            return 500
        case .beastV1:
            return 2000
        }
    }

    public var defaultDHTBootstrapNodes: [String] {
        switch self {
        case .baseline:
            return []
        case .animekoParityV1, .animekoParityV2, .qBittorrentParityV1, .beastV1:
            return Self.commonDHTBootstrapNodes
        }
    }

    public var defaultTrackerPreset: [String] {
        switch self {
        case .baseline, .qBittorrentParityV1:
            return []
        case .animekoParityV1, .animekoParityV2, .beastV1:
            return Self.animekoTrackerPreset
        }
    }

    public func applying(to configuration: SessionConfiguration) -> SessionConfiguration {
        var updated = configuration

        switch self {
        case .baseline:
            return updated
        case .animekoParityV1:
            updated.connectionsLimit = 200
            updated.dhtBootstrapNodes = defaultDHTBootstrapNodes
            updated.trackerPresetURLs = defaultTrackerPreset
        case .animekoParityV2:
            updated.connectionsLimit = 1000
            updated.activeDownloadsLimit = -1
            updated.activeSeedsLimit = -1
            updated.activeCheckingLimit = -1
            updated.activeDistributedHashTableLimit = -1
            updated.activeTrackerLimit = -1
            updated.activeLocalPeerDiscoveryLimit = -1
            updated.activeTorrentLimit = -1
            updated.connectionSpeed = 100
            updated.torrentConnectBoost = 200
            updated.maxOutgoingRequestQueueSize = 2000
            updated.maxAllowedIncomingRequestQueueSize = 2000
            updated.aioThreads = 8
            updated.filePoolSize = 512
            updated.maxQueuedDiskBytes = 8 * 1024 * 1024
            updated.sendBufferWatermarkFactorPercent = 150
            updated.enableUPnP = true
            updated.enableNATPMP = true
            updated.dhtBootstrapNodes = defaultDHTBootstrapNodes
            updated.trackerPresetURLs = defaultTrackerPreset
        case .qBittorrentParityV1:
            updated.connectionsLimit = 500
            updated.activeDownloadsLimit = -1
            updated.activeSeedsLimit = -1
            updated.activeCheckingLimit = -1
            updated.activeDistributedHashTableLimit = -1
            updated.activeTrackerLimit = -1
            updated.activeLocalPeerDiscoveryLimit = -1
            updated.activeTorrentLimit = -1
            updated.announceToAllTrackers = false
            updated.announceToAllTiers = true
            updated.peerTurnover = 4
            updated.peerTurnoverCutoff = 90
            updated.peerTurnoverInterval = 300
            updated.connectionSpeed = 30
            updated.torrentConnectBoost = 50
            updated.mixedModeAlgorithm = .preferTCP
            updated.chokingAlgorithm = .fixedSlots
            updated.seedChokingAlgorithm = .fastestUpload
            updated.maxOutgoingRequestQueueSize = 500
            updated.maxAllowedIncomingRequestQueueSize = 200
            updated.enablePieceExtentAffinity = false
            updated.suggestMode = .noPieceSuggestions
            updated.aioThreads = 8
            updated.filePoolSize = 500
            updated.maxConcurrentHTTPAnnounces = 50
            updated.stopTrackerTimeout = 2
            updated.includeIPOverheadInRateLimit = false
            updated.allowMultipleConnectionsPerIP = false
            updated.validateHTTPSTrackers = true
            updated.enableSSRFMitigation = true
            updated.enableOutgoingTCP = true
            updated.enableIncomingTCP = true
            updated.enableOutgoingUTP = true
            updated.enableIncomingUTP = true
            updated.enableUPnP = true
            updated.enableNATPMP = true
            updated.dhtBootstrapNodes = defaultDHTBootstrapNodes
            updated.trackerPresetURLs = defaultTrackerPreset
        case .beastV1:
            updated.connectionsLimit = 2000
            updated.activeDownloadsLimit = -1
            updated.activeSeedsLimit = -1
            updated.activeCheckingLimit = -1
            updated.activeDistributedHashTableLimit = -1
            updated.activeTrackerLimit = -1
            updated.activeLocalPeerDiscoveryLimit = -1
            updated.activeTorrentLimit = -1
            updated.announceToAllTrackers = true
            updated.announceToAllTiers = true
            updated.peerTurnover = 8
            updated.peerTurnoverCutoff = 85
            updated.peerTurnoverInterval = 120
            updated.connectionSpeed = 120
            updated.torrentConnectBoost = 300
            updated.mixedModeAlgorithm = .peerProportional
            updated.chokingAlgorithm = .rateBased
            updated.seedChokingAlgorithm = .fastestUpload
            updated.maxOutgoingRequestQueueSize = 4000
            updated.maxAllowedIncomingRequestQueueSize = 4000
            updated.wholePiecesThreshold = 40
            updated.enablePieceExtentAffinity = true
            updated.suggestMode = .suggestReadCache
            updated.aioThreads = 16
            updated.filePoolSize = 2048
            updated.maxConcurrentHTTPAnnounces = 100
            updated.stopTrackerTimeout = 1
            updated.allowMultipleConnectionsPerIP = true
            updated.validateHTTPSTrackers = true
            updated.enableSSRFMitigation = true
            updated.enableOutgoingTCP = true
            updated.enableIncomingTCP = true
            updated.enableOutgoingUTP = true
            updated.enableIncomingUTP = true
            updated.maxQueuedDiskBytes = 64 * 1024 * 1024
            updated.sendBufferLowWatermarkBytes = 128 * 1024
            updated.sendBufferWatermarkBytes = 4 * 1024 * 1024
            updated.sendBufferWatermarkFactorPercent = 200
            updated.enableUPnP = true
            updated.enableNATPMP = true
            updated.dhtBootstrapNodes = defaultDHTBootstrapNodes
            updated.trackerPresetURLs = defaultTrackerPreset
        }

        return updated
    }
}

private extension SessionProfile {
    static let commonDHTBootstrapNodes: [String] = [
        "router.utorrent.com:6881",
        "router.bittorrent.com:6881",
        "dht.transmissionbt.com:6881",
        "router.bitcomet.com:6881",
    ]

    static let animekoTrackerPreset: [String] = [
        "udp://tracker1.itzmx.com:8080/announce",
        "udp://moonburrow.club:6969/announce",
        "udp://new-line.net:6969/announce",
        "udp://opentracker.io:6969/announce",
        "udp://tamas3.ynh.fr:6969/announce",
        "udp://tracker.bittor.pw:1337/announce",
        "udp://tracker.dump.cl:6969/announce",
        "udp://tracker2.dler.org:80/announce",
        "https://tracker.tamersunion.org:443/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://tracker.moeking.me:6969/announce",
        "udp://tracker1.bt.moack.co.kr:80/announce",
        "udp://tracker.tiny-vps.com:6969/announce",
        "udp://bt1.archive.org:6969/announce",
        "udp://tracker.opentrackr.org:1337/announce",
        "http://tracker.opentrackr.org:1337/announce",
        "https://tracker1.520.jp:443/announce",
    ]
}

public extension SessionConfiguration {
    func applyingProfile(_ profile: SessionProfile) -> SessionConfiguration {
        profile.applying(to: self)
    }

    mutating func applyProfile(_ profile: SessionProfile) {
        self = profile.applying(to: self)
    }
}
