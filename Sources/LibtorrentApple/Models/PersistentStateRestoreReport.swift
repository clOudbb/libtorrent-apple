import Foundation

public struct PersistentStateRestoreReport: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable, Identifiable {
        public enum Outcome: String, Sendable, Hashable, Codable {
            case restored
            case degraded
            case failed
        }

        public let id: TorrentID
        public let name: String
        public let outcome: Outcome
        public let message: String

        public init(
            id: TorrentID,
            name: String,
            outcome: Outcome,
            message: String
        ) {
            self.id = id
            self.name = name
            self.outcome = outcome
            self.message = message
        }
    }

    public let restoredAt: Date
    public let entries: [Entry]

    public init(restoredAt: Date = Date(), entries: [Entry]) {
        self.restoredAt = restoredAt
        self.entries = entries
    }

    public var restoredCount: Int {
        entries.filter { $0.outcome == .restored }.count
    }

    public var degradedCount: Int {
        entries.filter { $0.outcome == .degraded }.count
    }

    public var failedCount: Int {
        entries.filter { $0.outcome == .failed }.count
    }
}

struct PersistentStateManifest: Sendable, Hashable, Codable {
    static let currentVersion = 1

    var version: Int
    var savedAt: Date
    var configuration: SessionConfiguration
    var torrents: [PersistentStateManifestTorrent]

    init(
        version: Int = Self.currentVersion,
        savedAt: Date = Date(),
        configuration: SessionConfiguration,
        torrents: [PersistentStateManifestTorrent]
    ) {
        self.version = version
        self.savedAt = savedAt
        self.configuration = configuration
        self.torrents = torrents
    }
}

struct PersistentStateManifestTorrent: Sendable, Hashable, Codable {
    var id: TorrentID
    var name: String
    var source: TorrentSource
    var downloadDirectory: URL
    var desiredState: TorrentState
    var addedAt: Date
    var updatedAt: Date
    var resumeDataFileName: String?
    var torrentFileName: String?
}

struct PersistentStateRestoreCandidate: Sendable {
    var manifestTorrent: PersistentStateManifestTorrent
    var resumeDataURL: URL?
    var torrentFileURL: URL?
}

struct PersistentStateTrackedArtifact: Sendable {
    var id: TorrentID
    var resumeDataURL: URL?
    var torrentFileURL: URL?
}

struct PersistentStateExportDescriptor: Sendable {
    var status: TorrentStatus
    var persistedResumeDataURL: URL?
    var persistedTorrentFileURL: URL?
}

struct PersistentStateExportContext: Sendable {
    var revision: UInt64
    var configuration: SessionConfiguration
    var torrents: [PersistentStateExportDescriptor]
}
