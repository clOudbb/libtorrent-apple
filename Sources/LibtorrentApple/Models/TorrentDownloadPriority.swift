import Foundation

public struct TorrentDownloadPriority: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: UInt8

    public init?(rawValue: UInt8) {
        guard rawValue <= 7 else {
            return nil
        }

        self.rawValue = rawValue
    }

    public init(rawValue: Int) {
        self.rawValue = UInt8(clamping: min(max(rawValue, 0), 7))
    }

    public static let doNotDownload = TorrentDownloadPriority(rawValue: 0)!
    public static let low = TorrentDownloadPriority(rawValue: 1)!
    public static let `default` = TorrentDownloadPriority(rawValue: 4)!
    public static let high = TorrentDownloadPriority(rawValue: 6)!
    public static let top = TorrentDownloadPriority(rawValue: 7)!

    public var isWanted: Bool {
        rawValue > 0
    }

    public static func < (lhs: TorrentDownloadPriority, rhs: TorrentDownloadPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
