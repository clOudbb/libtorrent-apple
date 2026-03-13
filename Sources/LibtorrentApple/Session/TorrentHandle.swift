import Foundation

public struct TorrentHandle: Sendable, Identifiable {
    public let id: TorrentID
    private let session: TorrentSession

    init(session: TorrentSession, id: TorrentID) {
        self.session = session
        self.id = id
    }

    public func status() async throws -> TorrentStatus {
        try await session.torrentStatus(for: id)
    }

    @discardableResult
    public func pause() async throws -> TorrentStatus {
        try await session.pauseTorrent(id: id)
    }

    @discardableResult
    public func resume() async throws -> TorrentStatus {
        try await session.resumeTorrent(id: id)
    }

    public func remove(deleteData: Bool = false) async throws {
        try await session.removeTorrent(id: id, deleteData: deleteData)
    }

    public func exportResumeData() async throws -> Data {
        try await session.exportNativeResumeData(for: id)
    }

    public func exportTorrentFile() async throws -> Data {
        try await session.exportTorrentFile(for: id)
    }

    public func downloadDirectory() async throws -> URL {
        try await session.downloadDirectory(for: id)
    }

    public func files() async throws -> [TorrentFile] {
        try await session.torrentFiles(for: id)
    }

    public func fileHandle(at index: Int) async throws -> TorrentFileHandle {
        _ = try await session.torrentFile(for: id, index: index)
        return TorrentFileHandle(session: session, torrentID: id, index: index)
    }

    public func downloadController() async throws -> TorrentDownloadController {
        guard let controller = await session.downloadController(for: id) else {
            throw LibtorrentAppleError.torrentNotFound(id)
        }

        return controller
    }

    @discardableResult
    public func setFilePriority(
        _ priority: TorrentDownloadPriority,
        at fileIndex: Int
    ) async throws -> TorrentFile {
        try await session.setFilePriority(priority, for: id, fileIndex: fileIndex)
    }

    public func setSequentialDownload(_ isEnabled: Bool) async throws {
        try await session.setSequentialDownload(isEnabled, for: id)
    }

    public func forceRecheck() async throws {
        try await session.forceRecheck(id: id)
    }

    public func forceReannounce(
        after seconds: Int = 0,
        trackerIndex: Int? = nil,
        ignoreMinimumInterval: Bool = false
    ) async throws {
        try await session.forceReannounce(
            id: id,
            after: seconds,
            trackerIndex: trackerIndex,
            ignoreMinimumInterval: ignoreMinimumInterval
        )
    }

    @discardableResult
    public func moveStorage(
        to directory: URL,
        strategy: TorrentStorageMoveStrategy = .replaceExisting
    ) async throws -> URL {
        try await session.moveStorage(for: id, to: directory, strategy: strategy)
    }

    public func piecePriorities() async throws -> [TorrentDownloadPriority] {
        try await session.piecePriorities(for: id)
    }

    public func trackers() async throws -> [TorrentTracker] {
        try await session.torrentTrackers(for: id)
    }

    @discardableResult
    public func replaceTrackers(_ trackers: [TorrentTrackerUpdate]) async throws -> [TorrentTracker] {
        try await session.replaceTrackers(trackers, for: id)
    }

    @discardableResult
    public func addTracker(_ tracker: TorrentTrackerUpdate) async throws -> [TorrentTracker] {
        try await session.addTracker(tracker, for: id)
    }

    public func peers() async throws -> [TorrentPeer] {
        try await session.torrentPeers(for: id)
    }

    public func pieces() async throws -> [TorrentPiece] {
        try await session.torrentPieces(for: id)
    }

    public func setPiecePriority(
        _ priority: TorrentDownloadPriority,
        at pieceIndex: Int
    ) async throws {
        try await session.setPiecePriority(priority, for: id, pieceIndex: pieceIndex)
    }

    public func setPieceDeadline(
        at pieceIndex: Int,
        milliseconds: Int
    ) async throws {
        try await session.setPieceDeadline(for: id, pieceIndex: pieceIndex, milliseconds: milliseconds)
    }

    public func resetPieceDeadline(at pieceIndex: Int) async throws {
        try await session.resetPieceDeadline(for: id, pieceIndex: pieceIndex)
    }
}
