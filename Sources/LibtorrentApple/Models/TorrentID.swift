import Foundation

public struct TorrentID: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public init() {
        let randomHex = (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        self.init(rawValue: String(randomHex.prefix(40)))
    }

    public var description: String {
        rawValue
    }
}
