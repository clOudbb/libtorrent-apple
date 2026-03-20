public enum SessionProfile: String, Sendable, Hashable, Codable {
    case baseline
    case animekoParityV1 = "animekoParity.v1"

    public var defaultConnectionsLimit: Int? {
        switch self {
        case .baseline:
            return nil
        case .animekoParityV1:
            return 200
        }
    }

    public var defaultDHTBootstrapNodes: [String] {
        switch self {
        case .baseline:
            return []
        case .animekoParityV1:
            return [
                "router.utorrent.com:6881",
                "router.bittorrent.com:6881",
                "dht.transmissionbt.com:6881",
                "router.bitcomet.com:6881",
            ]
        }
    }

    public var defaultTrackerPreset: [String] {
        switch self {
        case .baseline:
            return []
        case .animekoParityV1:
            return [
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
    }

    public func applying(to configuration: SessionConfiguration) -> SessionConfiguration {
        var updated = configuration
        if let connectionsLimit = defaultConnectionsLimit {
            updated.connectionsLimit = connectionsLimit
        }
        updated.dhtBootstrapNodes = defaultDHTBootstrapNodes
        return updated
    }
}

public extension SessionConfiguration {
    func applyingProfile(_ profile: SessionProfile) -> SessionConfiguration {
        profile.applying(to: self)
    }

    mutating func applyProfile(_ profile: SessionProfile) {
        self = profile.applying(to: self)
    }
}
