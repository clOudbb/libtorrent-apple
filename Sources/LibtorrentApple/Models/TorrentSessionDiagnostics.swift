public struct TorrentSessionDiagnostics: Sendable, Hashable, Codable {
    public var aggregateDownloadRateBytesPerSecond: Int64
    public var aggregateUploadRateBytesPerSecond: Int64
    public var totalConnections: Int
    public var totalPeers: Int
    public var totalSeeds: Int
    public var isDHTEnabled: Bool
    public var dhtNodeCount: Int

    public init(
        aggregateDownloadRateBytesPerSecond: Int64,
        aggregateUploadRateBytesPerSecond: Int64,
        totalConnections: Int,
        totalPeers: Int,
        totalSeeds: Int,
        isDHTEnabled: Bool,
        dhtNodeCount: Int
    ) {
        self.aggregateDownloadRateBytesPerSecond = aggregateDownloadRateBytesPerSecond
        self.aggregateUploadRateBytesPerSecond = aggregateUploadRateBytesPerSecond
        self.totalConnections = totalConnections
        self.totalPeers = totalPeers
        self.totalSeeds = totalSeeds
        self.isDHTEnabled = isDHTEnabled
        self.dhtNodeCount = dhtNodeCount
    }
}
