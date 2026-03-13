import Foundation

public struct EncodedTorrentInfo: Sendable, Hashable, Codable {
    public var data: Data
    public var sourceURL: URL?
    public var suggestedName: String?

    public init(
        data: Data,
        sourceURL: URL? = nil,
        suggestedName: String? = nil
    ) {
        self.data = data
        self.sourceURL = sourceURL
        self.suggestedName = suggestedName
    }
}
