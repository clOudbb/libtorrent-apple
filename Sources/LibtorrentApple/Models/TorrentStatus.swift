import Foundation

public struct TorrentStatus: Sendable, Hashable, Codable, Identifiable {
    public let id: TorrentID
    public var name: String
    public var source: TorrentSource
    public var downloadDirectory: URL?
    public var state: TorrentState
    public var metrics: TorrentMetrics
    public let addedAt: Date
    public var updatedAt: Date

    public init(
        id: TorrentID = TorrentID(),
        name: String,
        source: TorrentSource,
        downloadDirectory: URL? = nil,
        state: TorrentState = .idle,
        metrics: TorrentMetrics = .empty,
        addedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.downloadDirectory = downloadDirectory
        self.state = state
        self.metrics = metrics
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }
}
