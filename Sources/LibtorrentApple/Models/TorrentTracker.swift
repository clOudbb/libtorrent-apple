import Foundation

public struct TorrentTracker: Sendable, Hashable, Codable, Identifiable {
    public let torrentID: TorrentID
    public var url: String
    public var tier: Int
    public var failureCount: Int
    public var sourceMask: Int
    public var isVerified: Bool
    public var message: String?

    public init(
        torrentID: TorrentID,
        url: String,
        tier: Int,
        failureCount: Int,
        sourceMask: Int,
        isVerified: Bool,
        message: String? = nil
    ) {
        self.torrentID = torrentID
        self.url = url
        self.tier = tier
        self.failureCount = failureCount
        self.sourceMask = sourceMask
        self.isVerified = isVerified
        self.message = message
    }

    public var id: String {
        "\(torrentID.rawValue):\(url)"
    }
}
