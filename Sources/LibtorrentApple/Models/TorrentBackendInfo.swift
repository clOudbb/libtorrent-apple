public struct TorrentBackendInfo: Sendable, Hashable, Codable {
    public var vendor: String
    public var libraryVersion: String
    public var bridgeVersion: String
    public var packageName: String
    public var supportsHTTPSTrackers: Bool
    public var supportsSessionRuntimeSettings: Bool

    public init(
        vendor: String,
        libraryVersion: String,
        bridgeVersion: String,
        packageName: String,
        supportsHTTPSTrackers: Bool = false,
        supportsSessionRuntimeSettings: Bool = false
    ) {
        self.vendor = vendor
        self.libraryVersion = libraryVersion
        self.bridgeVersion = bridgeVersion
        self.packageName = packageName
        self.supportsHTTPSTrackers = supportsHTTPSTrackers
        self.supportsSessionRuntimeSettings = supportsSessionRuntimeSettings
    }

    enum CodingKeys: String, CodingKey {
        case vendor
        case libraryVersion
        case bridgeVersion
        case packageName
        case supportsHTTPSTrackers
        case supportsSessionRuntimeSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendor = try container.decode(String.self, forKey: .vendor)
        libraryVersion = try container.decode(String.self, forKey: .libraryVersion)
        bridgeVersion = try container.decode(String.self, forKey: .bridgeVersion)
        packageName = try container.decode(String.self, forKey: .packageName)
        supportsHTTPSTrackers = try container.decodeIfPresent(Bool.self, forKey: .supportsHTTPSTrackers) ?? false
        supportsSessionRuntimeSettings =
            try container.decodeIfPresent(Bool.self, forKey: .supportsSessionRuntimeSettings) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vendor, forKey: .vendor)
        try container.encode(libraryVersion, forKey: .libraryVersion)
        try container.encode(bridgeVersion, forKey: .bridgeVersion)
        try container.encode(packageName, forKey: .packageName)
        try container.encode(supportsHTTPSTrackers, forKey: .supportsHTTPSTrackers)
        try container.encode(supportsSessionRuntimeSettings, forKey: .supportsSessionRuntimeSettings)
    }
}
