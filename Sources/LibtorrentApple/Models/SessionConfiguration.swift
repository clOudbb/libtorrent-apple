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
    public var downloadDirectory: URL?
    public var listenInterfaces: [String]
    public var enableDistributedHashTable: Bool
    public var enableLocalPeerDiscovery: Bool
    public var enableUPnP: Bool
    public var enableNATPMP: Bool
    public var alertMask: Int32?
    public var userAgent: String
    public var handshakeClientVersion: String?
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
}
