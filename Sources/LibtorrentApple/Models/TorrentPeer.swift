import Foundation

public struct TorrentPeer: Sendable, Hashable, Codable, Identifiable {
    public let torrentID: TorrentID
    public var endpoint: String
    public var client: String
    public var flags: Int
    public var sourceMask: Int
    public var downloadRateBytesPerSecond: Int64
    public var uploadRateBytesPerSecond: Int64
    public var queueBytes: Int
    public var totalDownloadedBytes: Int64
    public var totalUploadedBytes: Int64
    public var progress: Double
    public var isSeed: Bool

    public init(
        torrentID: TorrentID,
        endpoint: String,
        client: String,
        flags: Int,
        sourceMask: Int,
        downloadRateBytesPerSecond: Int64,
        uploadRateBytesPerSecond: Int64,
        queueBytes: Int,
        totalDownloadedBytes: Int64,
        totalUploadedBytes: Int64,
        progress: Double,
        isSeed: Bool
    ) {
        self.torrentID = torrentID
        self.endpoint = endpoint
        self.client = client
        self.flags = flags
        self.sourceMask = sourceMask
        self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
        self.uploadRateBytesPerSecond = uploadRateBytesPerSecond
        self.queueBytes = queueBytes
        self.totalDownloadedBytes = totalDownloadedBytes
        self.totalUploadedBytes = totalUploadedBytes
        self.progress = progress
        self.isSeed = isSeed
    }

    public var id: String {
        "\(torrentID.rawValue):\(endpoint)"
    }
}
