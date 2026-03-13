import Foundation

public struct TorrentPieceSnapshot: Sendable, Hashable, Codable {
    public var torrentID: TorrentID
    public var pieces: [TorrentPiece]
    public var timestamp: Date

    public init(
        torrentID: TorrentID,
        pieces: [TorrentPiece],
        timestamp: Date = Date()
    ) {
        self.torrentID = torrentID
        self.pieces = pieces
        self.timestamp = timestamp
    }

    public var completedPieceCount: Int {
        pieces.lazy.filter(\.isDownloaded).count
    }

    public var wantedPieceCount: Int {
        pieces.lazy.filter { $0.priority.isWanted }.count
    }

    public var progress: Double {
        guard !pieces.isEmpty else {
            return 0
        }

        return Double(completedPieceCount) / Double(pieces.count)
    }
}
