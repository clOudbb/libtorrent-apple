import Foundation

public struct SessionProxyConfiguration: Sendable, Hashable, Codable {
    public enum ProxyType: Int32, Sendable, Hashable, Codable {
        case none = 0
        case socks4 = 1
        case socks5 = 2
        case socks5WithPassword = 3
        case http = 4
        case httpWithPassword = 5
    }

    public var type: ProxyType
    public var hostname: String
    public var port: Int
    public var username: String?
    public var password: String?
    public var proxyHostnames: Bool
    public var proxyPeerConnections: Bool
    public var proxyTrackerConnections: Bool

    public init(
        type: ProxyType,
        hostname: String,
        port: Int,
        username: String? = nil,
        password: String? = nil,
        proxyHostnames: Bool = true,
        proxyPeerConnections: Bool = true,
        proxyTrackerConnections: Bool = true
    ) {
        self.type = type
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.proxyHostnames = proxyHostnames
        self.proxyPeerConnections = proxyPeerConnections
        self.proxyTrackerConnections = proxyTrackerConnections
    }
}

public struct SessionEncryptionConfiguration: Sendable, Hashable, Codable {
    public enum Policy: Int32, Sendable, Hashable, Codable {
        case forced = 0
        case enabled = 1
        case disabled = 2
    }

    public enum Level: Int32, Sendable, Hashable, Codable {
        case plaintext = 1
        case rc4 = 2
        case both = 3
    }

    public var incomingPolicy: Policy
    public var outgoingPolicy: Policy
    public var allowedLevel: Level
    public var preferRC4: Bool

    public init(
        incomingPolicy: Policy = .enabled,
        outgoingPolicy: Policy = .enabled,
        allowedLevel: Level = .both,
        preferRC4: Bool = false
    ) {
        self.incomingPolicy = incomingPolicy
        self.outgoingPolicy = outgoingPolicy
        self.allowedLevel = allowedLevel
        self.preferRC4 = preferRC4
    }

    public static let `default` = SessionEncryptionConfiguration()
}

public enum SessionMixedModeAlgorithm: Int32, Sendable, Hashable, Codable {
    case preferTCP = 0
    case peerProportional = 1
}

public enum SessionChokingAlgorithm: Int32, Sendable, Hashable, Codable {
    case fixedSlots = 0
    case rateBased = 1
}

public enum SessionSeedChokingAlgorithm: Int32, Sendable, Hashable, Codable {
    case roundRobin = 0
    case fastestUpload = 1
    case antiLeech = 2
}

public enum SessionSuggestMode: Int32, Sendable, Hashable, Codable {
    case noPieceSuggestions = 0
    case suggestReadCache = 1
}

public enum SessionTransportBehavior: String, Sendable, Hashable, Codable {
    case balanced
    case preferTCP
    case tcpOnly
    case utpOnly
}

public struct SessionConfiguration: Sendable, Hashable, Codable {
    // Runtime apply behavior (when session is running, via TorrentSession.applyConfiguration):
    // - Requires session recreation if changed:
    //   downloadDirectory, listenInterfaces, enableDistributedHashTable, enableLocalPeerDiscovery,
    //   enableUPnP, enableNATPMP, alertMask, userAgent, handshakeClientVersion.
    // - Can be updated at runtime:
    //   peerFingerprint, dhtBootstrapNodes, shareRatioLimit, peerBlockedCIDRs, peerAllowedCIDRs,
    //   upload/download rate limits, connection/active limits (including -1 semantics), queue/request tuning,
    //   choking/mixed-mode/tracker announce tuning, send buffer tuning, autoSequentialDownload,
    //   proxy settings, encryption settings.
    // - Advanced optional fields (`announce*`, `peerTurnover*`, `mixed/choking`, `piece/suggest`,
    //   tracker timeout/concurrency, transport toggles, and related toggles) use nil as "leave unchanged".
    // Notes:
    // - shareRatioLimit is applied only when >= 0.
    // - Some runtime integer settings are clamped to non-negative values.
    // - Connection/active limits support -1 at runtime (libtorrent unlimited semantics).
    public var downloadDirectory: URL?
    public var listenInterfaces: [String]
    public var enableDistributedHashTable: Bool
    public var enableLocalPeerDiscovery: Bool
    public var enableUPnP: Bool
    public var enableNATPMP: Bool
    public var alertMask: Int32?
    public var userAgent: String
    public var handshakeClientVersion: String?
    public var peerFingerprint: String?
    public var dhtBootstrapNodes: [String]
    public var shareRatioLimit: Int
    public var peerBlockedCIDRs: [String]
    public var peerAllowedCIDRs: [String]
    public var uploadRateLimitBytesPerSecond: Int
    public var downloadRateLimitBytesPerSecond: Int
    public var connectionsLimit: Int
    public var activeDownloadsLimit: Int
    public var activeSeedsLimit: Int
    public var activeCheckingLimit: Int
    public var activeDistributedHashTableLimit: Int
    public var activeTrackerLimit: Int
    public var activeLocalPeerDiscoveryLimit: Int
    public var activeTorrentLimit: Int
    public var announceToAllTrackers: Bool?
    public var announceToAllTiers: Bool?
    public var peerTurnover: Int?
    public var peerTurnoverCutoff: Int?
    public var peerTurnoverInterval: Int?
    public var connectionSpeed: Int
    public var torrentConnectBoost: Int
    public var mixedModeAlgorithm: SessionMixedModeAlgorithm?
    public var chokingAlgorithm: SessionChokingAlgorithm?
    public var seedChokingAlgorithm: SessionSeedChokingAlgorithm?
    public var maxOutgoingRequestQueueSize: Int
    public var maxAllowedIncomingRequestQueueSize: Int
    public var wholePiecesThreshold: Int
    public var enablePieceExtentAffinity: Bool?
    public var suggestMode: SessionSuggestMode?
    public var aioThreads: Int
    public var checkingMemoryUsage: Int
    public var filePoolSize: Int
    public var maxConcurrentHTTPAnnounces: Int?
    public var stopTrackerTimeout: Int?
    public var includeIPOverheadInRateLimit: Bool?
    public var allowMultipleConnectionsPerIP: Bool?
    public var validateHTTPSTrackers: Bool?
    public var enableSSRFMitigation: Bool?
    public var enableOutgoingTCP: Bool?
    public var enableIncomingTCP: Bool?
    public var enableOutgoingUTP: Bool?
    public var enableIncomingUTP: Bool?
    public var maxQueuedDiskBytes: Int
    public var sendBufferLowWatermarkBytes: Int
    public var sendBufferWatermarkBytes: Int
    public var sendBufferWatermarkFactorPercent: Int
    public var autoSequentialDownload: Bool
    public var trackerPresetURLs: [String]
    public var proxy: SessionProxyConfiguration?
    public var encryption: SessionEncryptionConfiguration

    public init(
        downloadDirectory: URL? = nil,
        listenInterfaces: [String] = ["0.0.0.0:0", "[::]:0"],
        enableDistributedHashTable: Bool = true,
        enableLocalPeerDiscovery: Bool = true,
        enableUPnP: Bool = false,
        enableNATPMP: Bool = false,
        alertMask: Int32? = nil,
        userAgent: String = "libtorrent-apple/dev",
        handshakeClientVersion: String? = nil,
        peerFingerprint: String? = nil,
        dhtBootstrapNodes: [String] = [],
        shareRatioLimit: Int = -1,
        peerBlockedCIDRs: [String] = [],
        peerAllowedCIDRs: [String] = [],
        uploadRateLimitBytesPerSecond: Int = 0,
        downloadRateLimitBytesPerSecond: Int = 0,
        connectionsLimit: Int = 0,
        activeDownloadsLimit: Int = 0,
        activeSeedsLimit: Int = 0,
        activeCheckingLimit: Int = 0,
        activeDistributedHashTableLimit: Int = 0,
        activeTrackerLimit: Int = 0,
        activeLocalPeerDiscoveryLimit: Int = 0,
        activeTorrentLimit: Int = 0,
        announceToAllTrackers: Bool? = nil,
        announceToAllTiers: Bool? = nil,
        peerTurnover: Int? = nil,
        peerTurnoverCutoff: Int? = nil,
        peerTurnoverInterval: Int? = nil,
        connectionSpeed: Int = 0,
        torrentConnectBoost: Int = 0,
        mixedModeAlgorithm: SessionMixedModeAlgorithm? = nil,
        chokingAlgorithm: SessionChokingAlgorithm? = nil,
        seedChokingAlgorithm: SessionSeedChokingAlgorithm? = nil,
        maxOutgoingRequestQueueSize: Int = 0,
        maxAllowedIncomingRequestQueueSize: Int = 0,
        wholePiecesThreshold: Int = 0,
        enablePieceExtentAffinity: Bool? = nil,
        suggestMode: SessionSuggestMode? = nil,
        aioThreads: Int = 0,
        checkingMemoryUsage: Int = 0,
        filePoolSize: Int = 0,
        maxConcurrentHTTPAnnounces: Int? = nil,
        stopTrackerTimeout: Int? = nil,
        includeIPOverheadInRateLimit: Bool? = nil,
        allowMultipleConnectionsPerIP: Bool? = nil,
        validateHTTPSTrackers: Bool? = nil,
        enableSSRFMitigation: Bool? = nil,
        enableOutgoingTCP: Bool? = nil,
        enableIncomingTCP: Bool? = nil,
        enableOutgoingUTP: Bool? = nil,
        enableIncomingUTP: Bool? = nil,
        maxQueuedDiskBytes: Int = 0,
        sendBufferLowWatermarkBytes: Int = 0,
        sendBufferWatermarkBytes: Int = 0,
        sendBufferWatermarkFactorPercent: Int = 0,
        autoSequentialDownload: Bool = false,
        trackerPresetURLs: [String] = [],
        proxy: SessionProxyConfiguration? = nil,
        encryption: SessionEncryptionConfiguration = .default
    ) {
        self.downloadDirectory = downloadDirectory
        self.listenInterfaces = listenInterfaces
        self.enableDistributedHashTable = enableDistributedHashTable
        self.enableLocalPeerDiscovery = enableLocalPeerDiscovery
        self.enableUPnP = enableUPnP
        self.enableNATPMP = enableNATPMP
        self.alertMask = alertMask
        self.userAgent = userAgent
        self.handshakeClientVersion = handshakeClientVersion
        self.peerFingerprint = peerFingerprint
        self.dhtBootstrapNodes = dhtBootstrapNodes
        self.shareRatioLimit = shareRatioLimit
        self.peerBlockedCIDRs = peerBlockedCIDRs
        self.peerAllowedCIDRs = peerAllowedCIDRs
        self.uploadRateLimitBytesPerSecond = uploadRateLimitBytesPerSecond
        self.downloadRateLimitBytesPerSecond = downloadRateLimitBytesPerSecond
        self.connectionsLimit = connectionsLimit
        self.activeDownloadsLimit = activeDownloadsLimit
        self.activeSeedsLimit = activeSeedsLimit
        self.activeCheckingLimit = activeCheckingLimit
        self.activeDistributedHashTableLimit = activeDistributedHashTableLimit
        self.activeTrackerLimit = activeTrackerLimit
        self.activeLocalPeerDiscoveryLimit = activeLocalPeerDiscoveryLimit
        self.activeTorrentLimit = activeTorrentLimit
        self.announceToAllTrackers = announceToAllTrackers
        self.announceToAllTiers = announceToAllTiers
        self.peerTurnover = peerTurnover
        self.peerTurnoverCutoff = peerTurnoverCutoff
        self.peerTurnoverInterval = peerTurnoverInterval
        self.connectionSpeed = connectionSpeed
        self.torrentConnectBoost = torrentConnectBoost
        self.mixedModeAlgorithm = mixedModeAlgorithm
        self.chokingAlgorithm = chokingAlgorithm
        self.seedChokingAlgorithm = seedChokingAlgorithm
        self.maxOutgoingRequestQueueSize = maxOutgoingRequestQueueSize
        self.maxAllowedIncomingRequestQueueSize = maxAllowedIncomingRequestQueueSize
        self.wholePiecesThreshold = wholePiecesThreshold
        self.enablePieceExtentAffinity = enablePieceExtentAffinity
        self.suggestMode = suggestMode
        self.aioThreads = aioThreads
        self.checkingMemoryUsage = checkingMemoryUsage
        self.filePoolSize = filePoolSize
        self.maxConcurrentHTTPAnnounces = maxConcurrentHTTPAnnounces
        self.stopTrackerTimeout = stopTrackerTimeout
        self.includeIPOverheadInRateLimit = includeIPOverheadInRateLimit
        self.allowMultipleConnectionsPerIP = allowMultipleConnectionsPerIP
        self.validateHTTPSTrackers = validateHTTPSTrackers
        self.enableSSRFMitigation = enableSSRFMitigation
        self.enableOutgoingTCP = enableOutgoingTCP
        self.enableIncomingTCP = enableIncomingTCP
        self.enableOutgoingUTP = enableOutgoingUTP
        self.enableIncomingUTP = enableIncomingUTP
        self.maxQueuedDiskBytes = maxQueuedDiskBytes
        self.sendBufferLowWatermarkBytes = sendBufferLowWatermarkBytes
        self.sendBufferWatermarkBytes = sendBufferWatermarkBytes
        self.sendBufferWatermarkFactorPercent = sendBufferWatermarkFactorPercent
        self.autoSequentialDownload = autoSequentialDownload
        self.trackerPresetURLs = trackerPresetURLs
        self.proxy = proxy
        self.encryption = encryption
    }

    public static let `default` = SessionConfiguration()

    enum CodingKeys: String, CodingKey {
        case downloadDirectory
        case listenInterfaces
        case enableDistributedHashTable
        case enableLocalPeerDiscovery
        case enableUPnP
        case enableNATPMP
        case alertMask
        case userAgent
        case handshakeClientVersion
        case peerFingerprint
        case dhtBootstrapNodes
        case shareRatioLimit
        case peerBlockedCIDRs
        case peerAllowedCIDRs
        case uploadRateLimitBytesPerSecond
        case downloadRateLimitBytesPerSecond
        case connectionsLimit
        case activeDownloadsLimit
        case activeSeedsLimit
        case activeCheckingLimit
        case activeDistributedHashTableLimit
        case activeTrackerLimit
        case activeLocalPeerDiscoveryLimit
        case activeTorrentLimit
        case announceToAllTrackers
        case announceToAllTiers
        case peerTurnover
        case peerTurnoverCutoff
        case peerTurnoverInterval
        case connectionSpeed
        case torrentConnectBoost
        case mixedModeAlgorithm
        case chokingAlgorithm
        case seedChokingAlgorithm
        case maxOutgoingRequestQueueSize
        case maxAllowedIncomingRequestQueueSize
        case wholePiecesThreshold
        case enablePieceExtentAffinity
        case suggestMode
        case aioThreads
        case checkingMemoryUsage
        case filePoolSize
        case maxConcurrentHTTPAnnounces
        case stopTrackerTimeout
        case includeIPOverheadInRateLimit
        case allowMultipleConnectionsPerIP
        case validateHTTPSTrackers
        case enableSSRFMitigation
        case enableOutgoingTCP
        case enableIncomingTCP
        case enableOutgoingUTP
        case enableIncomingUTP
        case maxQueuedDiskBytes
        case sendBufferLowWatermarkBytes
        case sendBufferWatermarkBytes
        case sendBufferWatermarkFactorPercent
        case autoSequentialDownload
        case trackerPresetURLs
        case proxy
        case encryption
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SessionConfiguration.default

        downloadDirectory = try container.decodeIfPresent(URL.self, forKey: .downloadDirectory)
        listenInterfaces = try container.decodeIfPresent([String].self, forKey: .listenInterfaces) ?? defaults.listenInterfaces
        enableDistributedHashTable = try container.decodeIfPresent(Bool.self, forKey: .enableDistributedHashTable)
            ?? defaults.enableDistributedHashTable
        enableLocalPeerDiscovery = try container.decodeIfPresent(Bool.self, forKey: .enableLocalPeerDiscovery)
            ?? defaults.enableLocalPeerDiscovery
        enableUPnP = try container.decodeIfPresent(Bool.self, forKey: .enableUPnP) ?? defaults.enableUPnP
        enableNATPMP = try container.decodeIfPresent(Bool.self, forKey: .enableNATPMP) ?? defaults.enableNATPMP
        alertMask = try container.decodeIfPresent(Int32.self, forKey: .alertMask)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent) ?? defaults.userAgent
        handshakeClientVersion = try container.decodeIfPresent(String.self, forKey: .handshakeClientVersion)
        peerFingerprint = try container.decodeIfPresent(String.self, forKey: .peerFingerprint)
        dhtBootstrapNodes = try container.decodeIfPresent([String].self, forKey: .dhtBootstrapNodes) ?? []
        shareRatioLimit = try container.decodeIfPresent(Int.self, forKey: .shareRatioLimit) ?? defaults.shareRatioLimit
        peerBlockedCIDRs = try container.decodeIfPresent([String].self, forKey: .peerBlockedCIDRs) ?? defaults.peerBlockedCIDRs
        peerAllowedCIDRs = try container.decodeIfPresent([String].self, forKey: .peerAllowedCIDRs) ?? defaults.peerAllowedCIDRs
        uploadRateLimitBytesPerSecond = try container.decodeIfPresent(Int.self, forKey: .uploadRateLimitBytesPerSecond)
            ?? defaults.uploadRateLimitBytesPerSecond
        downloadRateLimitBytesPerSecond = try container.decodeIfPresent(Int.self, forKey: .downloadRateLimitBytesPerSecond)
            ?? defaults.downloadRateLimitBytesPerSecond
        connectionsLimit = try container.decodeIfPresent(Int.self, forKey: .connectionsLimit) ?? defaults.connectionsLimit
        activeDownloadsLimit = try container.decodeIfPresent(Int.self, forKey: .activeDownloadsLimit) ?? defaults.activeDownloadsLimit
        activeSeedsLimit = try container.decodeIfPresent(Int.self, forKey: .activeSeedsLimit) ?? defaults.activeSeedsLimit
        activeCheckingLimit = try container.decodeIfPresent(Int.self, forKey: .activeCheckingLimit) ?? defaults.activeCheckingLimit
        activeDistributedHashTableLimit =
            try container.decodeIfPresent(Int.self, forKey: .activeDistributedHashTableLimit)
                ?? defaults.activeDistributedHashTableLimit
        activeTrackerLimit = try container.decodeIfPresent(Int.self, forKey: .activeTrackerLimit) ?? defaults.activeTrackerLimit
        activeLocalPeerDiscoveryLimit =
            try container.decodeIfPresent(Int.self, forKey: .activeLocalPeerDiscoveryLimit)
                ?? defaults.activeLocalPeerDiscoveryLimit
        activeTorrentLimit = try container.decodeIfPresent(Int.self, forKey: .activeTorrentLimit) ?? defaults.activeTorrentLimit
        announceToAllTrackers = try container.decodeIfPresent(Bool.self, forKey: .announceToAllTrackers)
        announceToAllTiers = try container.decodeIfPresent(Bool.self, forKey: .announceToAllTiers)
        peerTurnover = try container.decodeIfPresent(Int.self, forKey: .peerTurnover)
        peerTurnoverCutoff = try container.decodeIfPresent(Int.self, forKey: .peerTurnoverCutoff)
        peerTurnoverInterval = try container.decodeIfPresent(Int.self, forKey: .peerTurnoverInterval)
        connectionSpeed = try container.decodeIfPresent(Int.self, forKey: .connectionSpeed) ?? defaults.connectionSpeed
        torrentConnectBoost = try container.decodeIfPresent(Int.self, forKey: .torrentConnectBoost) ?? defaults.torrentConnectBoost
        mixedModeAlgorithm =
            try container.decodeIfPresent(SessionMixedModeAlgorithm.self, forKey: .mixedModeAlgorithm)
        chokingAlgorithm =
            try container.decodeIfPresent(SessionChokingAlgorithm.self, forKey: .chokingAlgorithm)
        seedChokingAlgorithm =
            try container.decodeIfPresent(SessionSeedChokingAlgorithm.self, forKey: .seedChokingAlgorithm)
        maxOutgoingRequestQueueSize =
            try container.decodeIfPresent(Int.self, forKey: .maxOutgoingRequestQueueSize)
                ?? defaults.maxOutgoingRequestQueueSize
        maxAllowedIncomingRequestQueueSize =
            try container.decodeIfPresent(Int.self, forKey: .maxAllowedIncomingRequestQueueSize)
                ?? defaults.maxAllowedIncomingRequestQueueSize
        wholePiecesThreshold = try container.decodeIfPresent(Int.self, forKey: .wholePiecesThreshold) ?? defaults.wholePiecesThreshold
        enablePieceExtentAffinity = try container.decodeIfPresent(Bool.self, forKey: .enablePieceExtentAffinity)
        suggestMode = try container.decodeIfPresent(SessionSuggestMode.self, forKey: .suggestMode)
        aioThreads = try container.decodeIfPresent(Int.self, forKey: .aioThreads) ?? defaults.aioThreads
        checkingMemoryUsage = try container.decodeIfPresent(Int.self, forKey: .checkingMemoryUsage) ?? defaults.checkingMemoryUsage
        filePoolSize = try container.decodeIfPresent(Int.self, forKey: .filePoolSize) ?? defaults.filePoolSize
        maxConcurrentHTTPAnnounces = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentHTTPAnnounces)
        stopTrackerTimeout = try container.decodeIfPresent(Int.self, forKey: .stopTrackerTimeout)
        includeIPOverheadInRateLimit = try container.decodeIfPresent(Bool.self, forKey: .includeIPOverheadInRateLimit)
        allowMultipleConnectionsPerIP = try container.decodeIfPresent(Bool.self, forKey: .allowMultipleConnectionsPerIP)
        validateHTTPSTrackers = try container.decodeIfPresent(Bool.self, forKey: .validateHTTPSTrackers)
        enableSSRFMitigation = try container.decodeIfPresent(Bool.self, forKey: .enableSSRFMitigation)
        enableOutgoingTCP = try container.decodeIfPresent(Bool.self, forKey: .enableOutgoingTCP)
        enableIncomingTCP = try container.decodeIfPresent(Bool.self, forKey: .enableIncomingTCP)
        enableOutgoingUTP = try container.decodeIfPresent(Bool.self, forKey: .enableOutgoingUTP)
        enableIncomingUTP = try container.decodeIfPresent(Bool.self, forKey: .enableIncomingUTP)
        maxQueuedDiskBytes = try container.decodeIfPresent(Int.self, forKey: .maxQueuedDiskBytes) ?? defaults.maxQueuedDiskBytes
        sendBufferLowWatermarkBytes =
            try container.decodeIfPresent(Int.self, forKey: .sendBufferLowWatermarkBytes)
                ?? defaults.sendBufferLowWatermarkBytes
        sendBufferWatermarkBytes =
            try container.decodeIfPresent(Int.self, forKey: .sendBufferWatermarkBytes)
                ?? defaults.sendBufferWatermarkBytes
        sendBufferWatermarkFactorPercent =
            try container.decodeIfPresent(Int.self, forKey: .sendBufferWatermarkFactorPercent)
                ?? defaults.sendBufferWatermarkFactorPercent
        autoSequentialDownload = try container.decodeIfPresent(Bool.self, forKey: .autoSequentialDownload)
            ?? defaults.autoSequentialDownload
        trackerPresetURLs = try container.decodeIfPresent([String].self, forKey: .trackerPresetURLs) ?? defaults.trackerPresetURLs
        proxy = try container.decodeIfPresent(SessionProxyConfiguration.self, forKey: .proxy)
        encryption = try container.decodeIfPresent(SessionEncryptionConfiguration.self, forKey: .encryption)
            ?? defaults.encryption
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(downloadDirectory, forKey: .downloadDirectory)
        try container.encode(listenInterfaces, forKey: .listenInterfaces)
        try container.encode(enableDistributedHashTable, forKey: .enableDistributedHashTable)
        try container.encode(enableLocalPeerDiscovery, forKey: .enableLocalPeerDiscovery)
        try container.encode(enableUPnP, forKey: .enableUPnP)
        try container.encode(enableNATPMP, forKey: .enableNATPMP)
        try container.encodeIfPresent(alertMask, forKey: .alertMask)
        try container.encode(userAgent, forKey: .userAgent)
        try container.encodeIfPresent(handshakeClientVersion, forKey: .handshakeClientVersion)
        try container.encodeIfPresent(peerFingerprint, forKey: .peerFingerprint)
        try container.encode(dhtBootstrapNodes, forKey: .dhtBootstrapNodes)
        try container.encode(shareRatioLimit, forKey: .shareRatioLimit)
        try container.encode(peerBlockedCIDRs, forKey: .peerBlockedCIDRs)
        try container.encode(peerAllowedCIDRs, forKey: .peerAllowedCIDRs)
        try container.encode(uploadRateLimitBytesPerSecond, forKey: .uploadRateLimitBytesPerSecond)
        try container.encode(downloadRateLimitBytesPerSecond, forKey: .downloadRateLimitBytesPerSecond)
        try container.encode(connectionsLimit, forKey: .connectionsLimit)
        try container.encode(activeDownloadsLimit, forKey: .activeDownloadsLimit)
        try container.encode(activeSeedsLimit, forKey: .activeSeedsLimit)
        try container.encode(activeCheckingLimit, forKey: .activeCheckingLimit)
        try container.encode(activeDistributedHashTableLimit, forKey: .activeDistributedHashTableLimit)
        try container.encode(activeTrackerLimit, forKey: .activeTrackerLimit)
        try container.encode(activeLocalPeerDiscoveryLimit, forKey: .activeLocalPeerDiscoveryLimit)
        try container.encode(activeTorrentLimit, forKey: .activeTorrentLimit)
        try container.encodeIfPresent(announceToAllTrackers, forKey: .announceToAllTrackers)
        try container.encodeIfPresent(announceToAllTiers, forKey: .announceToAllTiers)
        try container.encodeIfPresent(peerTurnover, forKey: .peerTurnover)
        try container.encodeIfPresent(peerTurnoverCutoff, forKey: .peerTurnoverCutoff)
        try container.encodeIfPresent(peerTurnoverInterval, forKey: .peerTurnoverInterval)
        try container.encode(connectionSpeed, forKey: .connectionSpeed)
        try container.encode(torrentConnectBoost, forKey: .torrentConnectBoost)
        try container.encodeIfPresent(mixedModeAlgorithm, forKey: .mixedModeAlgorithm)
        try container.encodeIfPresent(chokingAlgorithm, forKey: .chokingAlgorithm)
        try container.encodeIfPresent(seedChokingAlgorithm, forKey: .seedChokingAlgorithm)
        try container.encode(maxOutgoingRequestQueueSize, forKey: .maxOutgoingRequestQueueSize)
        try container.encode(maxAllowedIncomingRequestQueueSize, forKey: .maxAllowedIncomingRequestQueueSize)
        try container.encode(wholePiecesThreshold, forKey: .wholePiecesThreshold)
        try container.encodeIfPresent(enablePieceExtentAffinity, forKey: .enablePieceExtentAffinity)
        try container.encodeIfPresent(suggestMode, forKey: .suggestMode)
        try container.encode(aioThreads, forKey: .aioThreads)
        try container.encode(checkingMemoryUsage, forKey: .checkingMemoryUsage)
        try container.encode(filePoolSize, forKey: .filePoolSize)
        try container.encodeIfPresent(maxConcurrentHTTPAnnounces, forKey: .maxConcurrentHTTPAnnounces)
        try container.encodeIfPresent(stopTrackerTimeout, forKey: .stopTrackerTimeout)
        try container.encodeIfPresent(includeIPOverheadInRateLimit, forKey: .includeIPOverheadInRateLimit)
        try container.encodeIfPresent(allowMultipleConnectionsPerIP, forKey: .allowMultipleConnectionsPerIP)
        try container.encodeIfPresent(validateHTTPSTrackers, forKey: .validateHTTPSTrackers)
        try container.encodeIfPresent(enableSSRFMitigation, forKey: .enableSSRFMitigation)
        try container.encodeIfPresent(enableOutgoingTCP, forKey: .enableOutgoingTCP)
        try container.encodeIfPresent(enableIncomingTCP, forKey: .enableIncomingTCP)
        try container.encodeIfPresent(enableOutgoingUTP, forKey: .enableOutgoingUTP)
        try container.encodeIfPresent(enableIncomingUTP, forKey: .enableIncomingUTP)
        try container.encode(maxQueuedDiskBytes, forKey: .maxQueuedDiskBytes)
        try container.encode(sendBufferLowWatermarkBytes, forKey: .sendBufferLowWatermarkBytes)
        try container.encode(sendBufferWatermarkBytes, forKey: .sendBufferWatermarkBytes)
        try container.encode(sendBufferWatermarkFactorPercent, forKey: .sendBufferWatermarkFactorPercent)
        try container.encode(autoSequentialDownload, forKey: .autoSequentialDownload)
        try container.encode(trackerPresetURLs, forKey: .trackerPresetURLs)
        try container.encodeIfPresent(proxy, forKey: .proxy)
        try container.encode(encryption, forKey: .encryption)
    }
}

public extension SessionConfiguration {
    func applyingTransportBehavior(_ behavior: SessionTransportBehavior) -> SessionConfiguration {
        var updated = self
        updated.applyTransportBehavior(behavior)
        return updated
    }

    mutating func applyTransportBehavior(_ behavior: SessionTransportBehavior) {
        switch behavior {
        case .balanced:
            enableOutgoingTCP = true
            enableIncomingTCP = true
            enableOutgoingUTP = true
            enableIncomingUTP = true
            mixedModeAlgorithm = .peerProportional
        case .preferTCP:
            enableOutgoingTCP = true
            enableIncomingTCP = true
            enableOutgoingUTP = true
            enableIncomingUTP = true
            mixedModeAlgorithm = .preferTCP
        case .tcpOnly:
            enableOutgoingTCP = true
            enableIncomingTCP = true
            enableOutgoingUTP = false
            enableIncomingUTP = false
            mixedModeAlgorithm = .preferTCP
        case .utpOnly:
            enableOutgoingTCP = false
            enableIncomingTCP = false
            enableOutgoingUTP = true
            enableIncomingUTP = true
            mixedModeAlgorithm = .peerProportional
        }
    }
}
