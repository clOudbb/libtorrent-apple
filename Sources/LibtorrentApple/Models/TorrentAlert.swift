import Foundation

public struct TorrentAlert: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case sessionStarted
        case sessionStopped
        case torrentAdded
        case torrentPaused
        case torrentResumed
        case torrentRemoved
        case torrentRechecked
        case torrentReannounced
        case torrentStorageMoved
        case sequentialDownloadChanged
        case torrentMetadataReceived
        case torrentStateChanged
        case torrentFinished
        case torrentTrackerError
        case torrentPerformanceWarning
        case torrentFilePriorityChanged
        case torrentPiecePriorityChanged
        case torrentPieceDeadlineChanged
        case torrentTrackersReplaced
        case torrentTrackerAdded
        case torrentTrackerWarning
        case torrentFileDataDeleted
        case torrentMetadataExported
        case resumeDataExported
        case resumeDataExportFailed
        case resumeDataRestored
        case nativeEvent
    }

    public let id: UUID
    public let kind: Kind
    public let torrentID: TorrentID?
    public let nativeTypeCode: Int32?
    public let nativeEventName: String?
    public let message: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        torrentID: TorrentID? = nil,
        nativeTypeCode: Int32? = nil,
        nativeEventName: String? = nil,
        message: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.torrentID = torrentID
        self.nativeTypeCode = nativeTypeCode
        self.nativeEventName = nativeEventName
        self.message = message
        self.timestamp = timestamp
    }
}
