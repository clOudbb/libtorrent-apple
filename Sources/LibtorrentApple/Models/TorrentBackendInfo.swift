public struct TorrentBackendInfo: Sendable, Hashable, Codable {
    public var vendor: String
    public var libraryVersion: String
    public var bridgeVersion: String
    public var packageName: String

    public init(
        vendor: String,
        libraryVersion: String,
        bridgeVersion: String,
        packageName: String
    ) {
        self.vendor = vendor
        self.libraryVersion = libraryVersion
        self.bridgeVersion = bridgeVersion
        self.packageName = packageName
    }
}
