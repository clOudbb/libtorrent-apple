import Foundation

public struct TorrentDownloadController: Sendable {
    public let torrentID: TorrentID

    private let session: TorrentSession

    init(session: TorrentSession, torrentID: TorrentID) {
        self.session = session
        self.torrentID = torrentID
    }

    public func snapshot() async throws -> TorrentPieceSnapshot {
        let pieces = try await session.torrentPieces(for: torrentID)
        return TorrentPieceSnapshot(torrentID: torrentID, pieces: pieces)
    }

    public func updates(
        pollInterval: Duration = .seconds(1),
        emitInitialValue: Bool = true,
        onlyChanges: Bool = true
    ) -> AsyncThrowingStream<TorrentPieceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastSnapshot: TorrentPieceSnapshot?

                if emitInitialValue {
                    let initialSnapshot = try await snapshot()
                    continuation.yield(initialSnapshot)
                    lastSnapshot = initialSnapshot
                }

                while !Task.isCancelled {
                    try await Task.sleep(for: pollInterval)
                    let nextSnapshot = try await snapshot()
                    if !onlyChanges || nextSnapshot.pieces != lastSnapshot?.pieces {
                        continuation.yield(nextSnapshot)
                        lastSnapshot = nextSnapshot
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func setSequentialMode(_ isEnabled: Bool) async throws {
        try await session.setSequentialDownload(isEnabled, for: torrentID)
    }

    public func prioritizePieces(
        _ pieceIndices: [Int],
        priority: TorrentDownloadPriority
    ) async throws {
        for pieceIndex in normalizedIndices(pieceIndices) {
            try await session.setPiecePriority(priority, for: torrentID, pieceIndex: pieceIndex)
        }
    }

    public func setDeadlines(
        for pieceIndices: [Int],
        milliseconds: Int
    ) async throws {
        for pieceIndex in normalizedIndices(pieceIndices) {
            try await session.setPieceDeadline(
                for: torrentID,
                pieceIndex: pieceIndex,
                milliseconds: milliseconds
            )
        }
    }

    public func clearDeadlines(for pieceIndices: [Int]) async throws {
        for pieceIndex in normalizedIndices(pieceIndices) {
            try await session.resetPieceDeadline(for: torrentID, pieceIndex: pieceIndex)
        }
    }

    public func prioritizeFiles(
        _ fileIndices: [Int],
        priority: TorrentDownloadPriority = .high,
        excludeOtherFiles: Bool = false
    ) async throws -> [TorrentFile] {
        let files = try await session.torrentFiles(for: torrentID)
        let requested = Set(normalizedIndices(fileIndices))

        if excludeOtherFiles {
            for file in files where !requested.contains(file.index) {
                _ = try await session.setFilePriority(.doNotDownload, for: torrentID, fileIndex: file.index)
            }
        }

        for fileIndex in requested {
            _ = try await session.setFilePriority(priority, for: torrentID, fileIndex: fileIndex)
        }

        return try await session.torrentFiles(for: torrentID)
    }

    @discardableResult
    public func prepareForStreaming(
        fileIndex: Int,
        leadPieceCount: Int = 8,
        deadlineMilliseconds: Int = 1_500,
        includeOnlySelectedFile: Bool = false
    ) async throws -> TorrentPieceSnapshot {
        let files = try await session.torrentFiles(for: torrentID)
        let pieces = try await session.torrentPieces(for: torrentID)

        guard let file = files.first(where: { $0.index == fileIndex }) else {
            throw LibtorrentAppleError.torrentFileNotFound(torrentID, fileIndex)
        }

        _ = try await prioritizeFiles(
            [fileIndex],
            priority: .high,
            excludeOtherFiles: includeOnlySelectedFile
        )
        try await session.setSequentialDownload(true, for: torrentID)

        let pieceWindow = streamingWindow(
            for: file,
            among: files,
            totalPieces: pieces.count,
            leadPieceCount: leadPieceCount
        )
        try await prioritizePieces(pieceWindow, priority: .top)
        try await setDeadlines(for: pieceWindow, milliseconds: deadlineMilliseconds)

        return try await snapshot()
    }

    private func normalizedIndices(_ indices: [Int]) -> [Int] {
        Array(Set(indices.filter { $0 >= 0 })).sorted()
    }

    private func streamingWindow(
        for file: TorrentFile,
        among files: [TorrentFile],
        totalPieces: Int,
        leadPieceCount: Int
    ) -> [Int] {
        guard totalPieces > 0 else {
            return []
        }

        let orderedFiles = files.sorted { $0.index < $1.index }
        let prefixSize = orderedFiles
            .prefix { $0.index < file.index }
            .reduce(Int64(0)) { $0 + max($1.sizeBytes, 0) }
        let totalSize = max(orderedFiles.reduce(Int64(0)) { $0 + max($1.sizeBytes, 0) }, 1)
        let fileStartRatio = Double(prefixSize) / Double(totalSize)
        let approximateStartPiece = min(
            max(Int((Double(totalPieces) * fileStartRatio).rounded(.down)), 0),
            max(totalPieces - 1, 0)
        )
        let windowSize = max(leadPieceCount, 1)
        let endPiece = min(approximateStartPiece + windowSize - 1, totalPieces - 1)
        return Array(approximateStartPiece ... endPiece)
    }
}
