public struct TorrentDownloaderStats: Sendable, Hashable, Codable {
    public var torrentCount: Int
    public var runningTorrentCount: Int
    public var pausedTorrentCount: Int
    public var totalDownloadedBytes: Int64
    public var totalUploadedBytes: Int64
    public var totalSizeBytes: Int64
    public var aggregateDownloadRateBytesPerSecond: Int64
    public var aggregateUploadRateBytesPerSecond: Int64

    public init(
        torrentCount: Int = 0,
        runningTorrentCount: Int = 0,
        pausedTorrentCount: Int = 0,
        totalDownloadedBytes: Int64 = 0,
        totalUploadedBytes: Int64 = 0,
        totalSizeBytes: Int64 = 0,
        aggregateDownloadRateBytesPerSecond: Int64 = 0,
        aggregateUploadRateBytesPerSecond: Int64 = 0
    ) {
        self.torrentCount = torrentCount
        self.runningTorrentCount = runningTorrentCount
        self.pausedTorrentCount = pausedTorrentCount
        self.totalDownloadedBytes = totalDownloadedBytes
        self.totalUploadedBytes = totalUploadedBytes
        self.totalSizeBytes = totalSizeBytes
        self.aggregateDownloadRateBytesPerSecond = aggregateDownloadRateBytesPerSecond
        self.aggregateUploadRateBytesPerSecond = aggregateUploadRateBytesPerSecond
    }

    public init(statuses: [TorrentStatus]) {
        self = statuses.reduce(into: .empty) { partialResult, status in
            partialResult.torrentCount += 1

            switch status.state {
            case .running:
                partialResult.runningTorrentCount += 1
            case .paused:
                partialResult.pausedTorrentCount += 1
            case .idle, .stopped, .removed:
                break
            }

            partialResult.totalDownloadedBytes += status.metrics.downloadedBytes
            partialResult.totalUploadedBytes += status.metrics.uploadedBytes
            partialResult.totalSizeBytes += status.metrics.totalSizeBytes
            partialResult.aggregateDownloadRateBytesPerSecond += status.metrics.downloadRateBytesPerSecond
            partialResult.aggregateUploadRateBytesPerSecond += status.metrics.uploadRateBytesPerSecond
        }
    }

    public static let empty = TorrentDownloaderStats()
}
