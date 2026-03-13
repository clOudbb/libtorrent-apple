import Foundation

public struct TorrentFile: Sendable, Hashable, Codable, Identifiable {
    public let torrentID: TorrentID
    public let index: Int
    public var path: String
    public var name: String
    public var sizeBytes: Int64
    public var downloadedBytes: Int64
    public var priority: TorrentDownloadPriority

    public init(
        torrentID: TorrentID,
        index: Int,
        path: String,
        name: String,
        sizeBytes: Int64,
        downloadedBytes: Int64,
        priority: TorrentDownloadPriority
    ) {
        self.torrentID = torrentID
        self.index = index
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.downloadedBytes = downloadedBytes
        self.priority = priority
    }

    public var id: String {
        "\(torrentID.rawValue):\(index)"
    }

    public var isWanted: Bool {
        priority.isWanted
    }

    public var progress: Double {
        guard sizeBytes > 0 else {
            return 0
        }

        return min(max(Double(downloadedBytes) / Double(sizeBytes), 0), 1)
    }
}
