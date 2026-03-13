import Foundation

public enum LibtorrentAppleError: Error, Sendable, Equatable {
    case bridgeUnavailable
    case nativeOperationFailed(Int32, String)
    case configurationInvalid(String)
    case invalidTorrentSource(URL)
    case invalidTorrentData(String)
    case unsupportedURLScheme(String)
    case networkTransferFailed(String)
    case sessionNotRunning
    case torrentNotFound(TorrentID)
    case torrentFileNotFound(TorrentID, Int)
    case torrentPieceNotFound(TorrentID, Int)
    case metadataUnavailable(TorrentID?)
    case trackerOperationFailed(String)
    case storageOperationFailed(String)
    case pieceControlFailed(String)
    case fileSystemOperationFailed(String)
    case operationTimedOut(String)
    case resumeDataEncodingFailed(String)
    case resumeDataDecodingFailed(String)
}

extension LibtorrentAppleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bridgeUnavailable:
            return "The native libtorrent bridge is not available."
        case let .nativeOperationFailed(code, message):
            return "The native libtorrent operation failed with code \(code): \(message)"
        case let .configurationInvalid(message):
            return "The session configuration is invalid: \(message)"
        case let .invalidTorrentSource(url):
            return "The torrent source is invalid for this operation: \(url.absoluteString)"
        case let .invalidTorrentData(message):
            return "The torrent data is invalid: \(message)"
        case let .unsupportedURLScheme(scheme):
            return "The URL scheme is not supported for torrent operations: \(scheme)"
        case let .networkTransferFailed(message):
            return "The torrent network transfer failed: \(message)"
        case .sessionNotRunning:
            return "The torrent session must be started before performing this operation."
        case let .torrentNotFound(id):
            return "No torrent exists for id \(id)."
        case let .torrentFileNotFound(id, index):
            return "No torrent file exists for id \(id) at index \(index)."
        case let .torrentPieceNotFound(id, index):
            return "No torrent piece exists for id \(id) at index \(index)."
        case let .metadataUnavailable(id):
            if let id {
                return "The torrent metadata is not available yet for \(id)."
            }
            return "The torrent metadata is not available yet."
        case let .trackerOperationFailed(message):
            return "The tracker operation failed: \(message)"
        case let .storageOperationFailed(message):
            return "The storage operation failed: \(message)"
        case let .pieceControlFailed(message):
            return "The piece control operation failed: \(message)"
        case let .fileSystemOperationFailed(message):
            return "The file system operation failed: \(message)"
        case let .operationTimedOut(message):
            return "The torrent operation timed out: \(message)"
        case let .resumeDataEncodingFailed(message):
            return "Failed to encode resume data: \(message)"
        case let .resumeDataDecodingFailed(message):
            return "Failed to decode resume data: \(message)"
        }
    }
}
