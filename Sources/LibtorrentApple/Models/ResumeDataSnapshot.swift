public struct ResumeDataSnapshot: Sendable, Hashable, Codable {
    public var configuration: SessionConfiguration
    public var torrents: [TorrentStatus]

    public init(configuration: SessionConfiguration, torrents: [TorrentStatus]) {
        self.configuration = configuration
        self.torrents = torrents
    }
}
