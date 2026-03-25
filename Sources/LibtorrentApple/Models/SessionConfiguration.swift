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

public struct SessionConfiguration: Sendable, Hashable, Codable {
    // Runtime apply behavior (when session is running, via TorrentSession.applyConfiguration):
    // - Requires session recreation if changed:
    //   downloadDirectory, listenInterfaces, enableDistributedHashTable, enableLocalPeerDiscovery,
    //   enableUPnP, enableNATPMP, alertMask, userAgent, handshakeClientVersion.
    // - Can be updated at runtime:
    //   peerFingerprint, dhtBootstrapNodes, shareRatioLimit, peerBlockedCIDRs, peerAllowedCIDRs,
    //   upload/download rate limits, connection/active limits, send buffer tuning, autoSequentialDownload,
    //   proxy settings, encryption settings.
    // Notes:
    // - shareRatioLimit is applied only when >= 0.
    // - Several integer limits are clamped to non-negative values during runtime apply.
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
    public var maxQueuedDiskBytes: Int
    public var sendBufferLowWatermarkBytes: Int
    public var sendBufferWatermarkBytes: Int
    public var sendBufferWatermarkFactorPercent: Int
    public var autoSequentialDownload: Bool
    public var proxy: SessionProxyConfiguration?
    public var encryption: SessionEncryptionConfiguration

    public init(
        downloadDirectory: URL? = nil,
        listenInterfaces: [String] = ["0.0.0.0:0"],
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
        maxQueuedDiskBytes: Int = 0,
        sendBufferLowWatermarkBytes: Int = 0,
        sendBufferWatermarkBytes: Int = 0,
        sendBufferWatermarkFactorPercent: Int = 0,
        autoSequentialDownload: Bool = false,
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
        self.maxQueuedDiskBytes = maxQueuedDiskBytes
        self.sendBufferLowWatermarkBytes = sendBufferLowWatermarkBytes
        self.sendBufferWatermarkBytes = sendBufferWatermarkBytes
        self.sendBufferWatermarkFactorPercent = sendBufferWatermarkFactorPercent
        self.autoSequentialDownload = autoSequentialDownload
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
        case maxQueuedDiskBytes
        case sendBufferLowWatermarkBytes
        case sendBufferWatermarkBytes
        case sendBufferWatermarkFactorPercent
        case autoSequentialDownload
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
        try container.encode(maxQueuedDiskBytes, forKey: .maxQueuedDiskBytes)
        try container.encode(sendBufferLowWatermarkBytes, forKey: .sendBufferLowWatermarkBytes)
        try container.encode(sendBufferWatermarkBytes, forKey: .sendBufferWatermarkBytes)
        try container.encode(sendBufferWatermarkFactorPercent, forKey: .sendBufferWatermarkFactorPercent)
        try container.encode(autoSequentialDownload, forKey: .autoSequentialDownload)
        try container.encodeIfPresent(proxy, forKey: .proxy)
        try container.encode(encryption, forKey: .encryption)
    }
}
