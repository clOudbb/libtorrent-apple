import Foundation

public struct TorrentPiece: Sendable, Hashable, Codable, Identifiable {
    public let torrentID: TorrentID
    public let index: Int
    public var priority: TorrentDownloadPriority
    public var availability: Int
    public var isDownloaded: Bool

    public init(
        torrentID: TorrentID,
        index: Int,
        priority: TorrentDownloadPriority,
        availability: Int,
        isDownloaded: Bool
    ) {
        self.torrentID = torrentID
        self.index = index
        self.priority = priority
        self.availability = availability
        self.isDownloaded = isDownloaded
    }

    public var id: String {
        "\(torrentID.rawValue):\(index)"
    }
}
