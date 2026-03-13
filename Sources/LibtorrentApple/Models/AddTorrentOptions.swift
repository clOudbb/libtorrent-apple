import Foundation

public struct AddTorrentOptions: Sendable, Hashable, Codable {
    public var displayName: String?
    public var downloadDirectory: URL?

    public init(
        displayName: String? = nil,
        downloadDirectory: URL? = nil
    ) {
        self.displayName = displayName
        self.downloadDirectory = downloadDirectory
    }

    public static let `default` = AddTorrentOptions()
}
