import Foundation

public struct TorrentSource: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case magnetLink
        case torrentFile
    }

    public let kind: Kind
    public let location: URL
    public let displayName: String?

    public init(kind: Kind, location: URL, displayName: String? = nil) {
        self.kind = kind
        self.location = location
        self.displayName = displayName
    }

    public static func magnetLink(_ location: URL, displayName: String? = nil) -> Self {
        Self(kind: .magnetLink, location: location, displayName: displayName)
    }

    public static func torrentFile(_ location: URL, displayName: String? = nil) -> Self {
        Self(kind: .torrentFile, location: location, displayName: displayName)
    }
}
