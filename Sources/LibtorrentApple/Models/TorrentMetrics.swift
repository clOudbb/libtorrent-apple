public struct TorrentMetrics: Sendable, Hashable, Codable {
    public var progress: Double
    public var downloadedBytes: Int64
    public var uploadedBytes: Int64
    public var totalSizeBytes: Int64
    public var downloadRateBytesPerSecond: Int64
    public var uploadRateBytesPerSecond: Int64
    public var peerCount: Int
    public var seedCount: Int

    public init(
        progress: Double = 0,
        downloadedBytes: Int64 = 0,
        uploadedBytes: Int64 = 0,
        totalSizeBytes: Int64 = 0,
        downloadRateBytesPerSecond: Int64 = 0,
        uploadRateBytesPerSecond: Int64 = 0,
        peerCount: Int = 0,
        seedCount: Int = 0
    ) {
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.totalSizeBytes = totalSizeBytes
        self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
        self.uploadRateBytesPerSecond = uploadRateBytesPerSecond
        self.peerCount = peerCount
        self.seedCount = seedCount
    }

    public static let empty = TorrentMetrics()
}
