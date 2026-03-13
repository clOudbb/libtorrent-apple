import Foundation

public struct TorrentFileHandle: Sendable, Identifiable {
    public let torrentID: TorrentID
    public let index: Int

    private let session: TorrentSession

    init(session: TorrentSession, torrentID: TorrentID, index: Int) {
        self.session = session
        self.torrentID = torrentID
        self.index = index
    }

    public var id: String {
        "\(torrentID.rawValue):\(index)"
    }

    public func file() async throws -> TorrentFile {
        try await session.torrentFile(for: torrentID, index: index)
    }

    @discardableResult
    public func setPriority(_ priority: TorrentDownloadPriority) async throws -> TorrentFile {
        try await session.setFilePriority(priority, for: torrentID, fileIndex: index)
        return try await file()
    }

    @discardableResult
    public func pause() async throws -> TorrentFile {
        try await setPriority(.doNotDownload)
    }

    @discardableResult
    public func exclude() async throws -> TorrentFile {
        try await pause()
    }

    @discardableResult
    public func resume(priority: TorrentDownloadPriority = .default) async throws -> TorrentFile {
        try await setPriority(priority)
    }

    @discardableResult
    public func include(priority: TorrentDownloadPriority = .default) async throws -> TorrentFile {
        try await resume(priority: priority)
    }

    @discardableResult
    public func deleteLocalData() async throws -> URL {
        try await session.deleteLocalFileData(for: torrentID, fileIndex: index)
    }
}
