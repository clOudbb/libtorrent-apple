public struct SessionRuntimePatch: Sendable, Hashable, Codable {
    public var uploadRateLimitBytesPerSecond: Int?
    public var downloadRateLimitBytesPerSecond: Int?
    public var connectionsLimit: Int?
    public var activeDownloadsLimit: Int?
    public var activeSeedsLimit: Int?
    public var activeCheckingLimit: Int?
    public var activeDistributedHashTableLimit: Int?
    public var activeTrackerLimit: Int?
    public var activeLocalPeerDiscoveryLimit: Int?
    public var activeTorrentLimit: Int?
    public var connectionSpeed: Int?
    public var torrentConnectBoost: Int?
    public var includeIPOverheadInRateLimit: Bool?
    public var allowMultipleConnectionsPerIP: Bool?
    public var enableOutgoingTCP: Bool?
    public var enableIncomingTCP: Bool?
    public var enableOutgoingUTP: Bool?
    public var enableIncomingUTP: Bool?
    public var mixedModeAlgorithm: SessionMixedModeAlgorithm?
    public var autoSequentialDownload: Bool?

    public init(
        uploadRateLimitBytesPerSecond: Int? = nil,
        downloadRateLimitBytesPerSecond: Int? = nil,
        connectionsLimit: Int? = nil,
        activeDownloadsLimit: Int? = nil,
        activeSeedsLimit: Int? = nil,
        activeCheckingLimit: Int? = nil,
        activeDistributedHashTableLimit: Int? = nil,
        activeTrackerLimit: Int? = nil,
        activeLocalPeerDiscoveryLimit: Int? = nil,
        activeTorrentLimit: Int? = nil,
        connectionSpeed: Int? = nil,
        torrentConnectBoost: Int? = nil,
        includeIPOverheadInRateLimit: Bool? = nil,
        allowMultipleConnectionsPerIP: Bool? = nil,
        enableOutgoingTCP: Bool? = nil,
        enableIncomingTCP: Bool? = nil,
        enableOutgoingUTP: Bool? = nil,
        enableIncomingUTP: Bool? = nil,
        mixedModeAlgorithm: SessionMixedModeAlgorithm? = nil,
        autoSequentialDownload: Bool? = nil
    ) {
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
        self.connectionSpeed = connectionSpeed
        self.torrentConnectBoost = torrentConnectBoost
        self.includeIPOverheadInRateLimit = includeIPOverheadInRateLimit
        self.allowMultipleConnectionsPerIP = allowMultipleConnectionsPerIP
        self.enableOutgoingTCP = enableOutgoingTCP
        self.enableIncomingTCP = enableIncomingTCP
        self.enableOutgoingUTP = enableOutgoingUTP
        self.enableIncomingUTP = enableIncomingUTP
        self.mixedModeAlgorithm = mixedModeAlgorithm
        self.autoSequentialDownload = autoSequentialDownload
    }

    public var isEmpty: Bool {
        uploadRateLimitBytesPerSecond == nil
            && downloadRateLimitBytesPerSecond == nil
            && connectionsLimit == nil
            && activeDownloadsLimit == nil
            && activeSeedsLimit == nil
            && activeCheckingLimit == nil
            && activeDistributedHashTableLimit == nil
            && activeTrackerLimit == nil
            && activeLocalPeerDiscoveryLimit == nil
            && activeTorrentLimit == nil
            && connectionSpeed == nil
            && torrentConnectBoost == nil
            && mixedModeAlgorithm == nil
            && includeIPOverheadInRateLimit == nil
            && allowMultipleConnectionsPerIP == nil
            && enableOutgoingTCP == nil
            && enableIncomingTCP == nil
            && enableOutgoingUTP == nil
            && enableIncomingUTP == nil
            && autoSequentialDownload == nil
    }

    func merging(_ patch: SessionRuntimePatch) -> SessionRuntimePatch {
        var merged = self
        merged.uploadRateLimitBytesPerSecond = patch.uploadRateLimitBytesPerSecond ?? merged.uploadRateLimitBytesPerSecond
        merged.downloadRateLimitBytesPerSecond = patch.downloadRateLimitBytesPerSecond ?? merged.downloadRateLimitBytesPerSecond
        merged.connectionsLimit = patch.connectionsLimit ?? merged.connectionsLimit
        merged.activeDownloadsLimit = patch.activeDownloadsLimit ?? merged.activeDownloadsLimit
        merged.activeSeedsLimit = patch.activeSeedsLimit ?? merged.activeSeedsLimit
        merged.activeCheckingLimit = patch.activeCheckingLimit ?? merged.activeCheckingLimit
        merged.activeDistributedHashTableLimit = patch.activeDistributedHashTableLimit ?? merged.activeDistributedHashTableLimit
        merged.activeTrackerLimit = patch.activeTrackerLimit ?? merged.activeTrackerLimit
        merged.activeLocalPeerDiscoveryLimit = patch.activeLocalPeerDiscoveryLimit ?? merged.activeLocalPeerDiscoveryLimit
        merged.activeTorrentLimit = patch.activeTorrentLimit ?? merged.activeTorrentLimit
        merged.connectionSpeed = patch.connectionSpeed ?? merged.connectionSpeed
        merged.torrentConnectBoost = patch.torrentConnectBoost ?? merged.torrentConnectBoost
        merged.includeIPOverheadInRateLimit = patch.includeIPOverheadInRateLimit ?? merged.includeIPOverheadInRateLimit
        merged.allowMultipleConnectionsPerIP = patch.allowMultipleConnectionsPerIP ?? merged.allowMultipleConnectionsPerIP
        merged.enableOutgoingTCP = patch.enableOutgoingTCP ?? merged.enableOutgoingTCP
        merged.enableIncomingTCP = patch.enableIncomingTCP ?? merged.enableIncomingTCP
        merged.enableOutgoingUTP = patch.enableOutgoingUTP ?? merged.enableOutgoingUTP
        merged.enableIncomingUTP = patch.enableIncomingUTP ?? merged.enableIncomingUTP
        merged.mixedModeAlgorithm = patch.mixedModeAlgorithm ?? merged.mixedModeAlgorithm
        merged.autoSequentialDownload = patch.autoSequentialDownload ?? merged.autoSequentialDownload
        return merged
    }

    public static func transportBehavior(_ behavior: SessionTransportBehavior) -> SessionRuntimePatch {
        switch behavior {
        case .balanced:
            return SessionRuntimePatch(
                enableOutgoingTCP: true,
                enableIncomingTCP: true,
                enableOutgoingUTP: true,
                enableIncomingUTP: true,
                mixedModeAlgorithm: .peerProportional
            )
        case .preferTCP:
            return SessionRuntimePatch(
                enableOutgoingTCP: true,
                enableIncomingTCP: true,
                enableOutgoingUTP: true,
                enableIncomingUTP: true,
                mixedModeAlgorithm: .preferTCP
            )
        case .tcpOnly:
            return SessionRuntimePatch(
                enableOutgoingTCP: true,
                enableIncomingTCP: true,
                enableOutgoingUTP: false,
                enableIncomingUTP: false,
                mixedModeAlgorithm: .preferTCP
            )
        case .utpOnly:
            return SessionRuntimePatch(
                enableOutgoingTCP: false,
                enableIncomingTCP: false,
                enableOutgoingUTP: true,
                enableIncomingUTP: true,
                mixedModeAlgorithm: .peerProportional
            )
        }
    }
}

extension SessionConfiguration {
    mutating func applyRuntimePatch(_ patch: SessionRuntimePatch) {
        if let value = patch.uploadRateLimitBytesPerSecond {
            uploadRateLimitBytesPerSecond = max(value, 0)
        }
        if let value = patch.downloadRateLimitBytesPerSecond {
            downloadRateLimitBytesPerSecond = max(value, 0)
        }
        if let value = patch.connectionsLimit {
            connectionsLimit = max(value, -1)
        }
        if let value = patch.activeDownloadsLimit {
            activeDownloadsLimit = max(value, -1)
        }
        if let value = patch.activeSeedsLimit {
            activeSeedsLimit = max(value, -1)
        }
        if let value = patch.activeCheckingLimit {
            activeCheckingLimit = max(value, -1)
        }
        if let value = patch.activeDistributedHashTableLimit {
            activeDistributedHashTableLimit = max(value, -1)
        }
        if let value = patch.activeTrackerLimit {
            activeTrackerLimit = max(value, -1)
        }
        if let value = patch.activeLocalPeerDiscoveryLimit {
            activeLocalPeerDiscoveryLimit = max(value, -1)
        }
        if let value = patch.activeTorrentLimit {
            activeTorrentLimit = max(value, -1)
        }
        if let value = patch.connectionSpeed {
            connectionSpeed = max(value, 0)
        }
        if let value = patch.torrentConnectBoost {
            torrentConnectBoost = max(value, 0)
        }
        if let value = patch.mixedModeAlgorithm {
            mixedModeAlgorithm = value
        }
        if let value = patch.includeIPOverheadInRateLimit {
            includeIPOverheadInRateLimit = value
        }
        if let value = patch.allowMultipleConnectionsPerIP {
            allowMultipleConnectionsPerIP = value
        }
        if let value = patch.enableOutgoingTCP {
            enableOutgoingTCP = value
        }
        if let value = patch.enableIncomingTCP {
            enableIncomingTCP = value
        }
        if let value = patch.enableOutgoingUTP {
            enableOutgoingUTP = value
        }
        if let value = patch.enableIncomingUTP {
            enableIncomingUTP = value
        }
        if let value = patch.autoSequentialDownload {
            autoSequentialDownload = value
        }
    }

}
