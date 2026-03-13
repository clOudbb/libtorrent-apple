import Foundation

public struct TorrentTrackerUpdate: Sendable, Hashable, Codable {
    public var url: String
    public var tier: Int

    public init(url: String, tier: Int = 0) {
        self.url = url
        self.tier = tier
    }
}
