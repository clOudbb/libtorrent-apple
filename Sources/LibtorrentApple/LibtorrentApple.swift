import Foundation

#if canImport(LibtorrentAppleBinary)
import LibtorrentAppleBinary
#elseif canImport(LibtorrentAppleBridge)
import LibtorrentAppleBridge
#else
#error("No libtorrent bridge module is available.")
#endif

typealias BridgeSessionHandle = OpaquePointer

struct BridgeNativeAlert: Sendable {
    let typeCode: Int32
    let name: String
    let message: String
    let torrentID: TorrentID?
}

struct BridgeNativeTorrentFile: Sendable {
    let index: Int
    let name: String
    let path: String
    let sizeBytes: Int64
    let downloadedBytes: Int64
    let priority: TorrentDownloadPriority
}

struct BridgeNativeTorrentTracker: Sendable {
    let url: String
    let tier: Int
    let failureCount: Int
    let sourceMask: Int
    let isVerified: Bool
    let message: String?
}

struct BridgeNativeTorrentPeer: Sendable {
    let endpoint: String
    let client: String
    let flags: Int
    let sourceMask: Int
    let downloadRateBytesPerSecond: Int64
    let uploadRateBytesPerSecond: Int64
    let queueBytes: Int
    let totalDownloadedBytes: Int64
    let totalUploadedBytes: Int64
    let progress: Double
    let isSeed: Bool
}

struct BridgeNativeTorrentPiece: Sendable {
    let index: Int
    let priority: TorrentDownloadPriority
    let availability: Int
    let isDownloaded: Bool
}

struct BridgeNativeSessionStats: Sendable, Equatable {
    let downloadRateBytesPerSecond: Int64
    let uploadRateBytesPerSecond: Int64
    let totalConnections: Int
    let totalPeers: Int
    let totalSeeds: Int
    let isDHTEnabled: Bool
    let dhtNodeCount: Int
}

public enum LibtorrentApple {
    public static let packageName = "LibtorrentApple"
    public static let bridgeVersion = String(cString: libtorrent_apple_bridge_version())
    public static let backendAvailable = libtorrent_apple_bridge_is_available()
    public static let backendInfo = TorrentBackendInfo(
        vendor: "libtorrent",
        libraryVersion: bridgeVersion,
        bridgeVersion: bridgeVersion,
        packageName: packageName
    )
}

enum BridgeRuntime {
    static func requireAvailable() throws {
        guard LibtorrentApple.backendAvailable else {
            throw LibtorrentAppleError.bridgeUnavailable
        }
    }

    static func createSession(configuration: SessionConfiguration) throws -> BridgeSessionHandle {
        try requireAvailable()

        var nativeConfiguration = makeNativeSessionConfiguration(from: configuration)

        var nativeSession: BridgeSessionHandle?
        var nativeError = libtorrent_apple_error_t()

        guard libtorrent_apple_session_create(&nativeConfiguration, &nativeSession, &nativeError) else {
            throw error(from: nativeError, fallbackMessage: "Failed to create libtorrent session.")
        }

        guard let nativeSession else {
            throw LibtorrentAppleError.nativeOperationFailed(-1, "Native bridge did not return a session handle.")
        }

        return nativeSession
    }

    static func applyConfiguration(session: BridgeSessionHandle, configuration: SessionConfiguration) throws {
        var nativeConfiguration = makeNativeSessionConfiguration(from: configuration)
        var nativeError = libtorrent_apple_error_t()

        #if canImport(LibtorrentAppleBridge) || canImport(LibtorrentAppleBinary)
        guard libtorrent_apple_session_apply_configuration(session, &nativeConfiguration, &nativeError) else {
            throw error(from: nativeError, fallbackMessage: "Failed to apply session configuration.")
        }
        #else
        throw LibtorrentAppleError.nativeOperationFailed(
            -1,
            "Runtime configuration apply is unavailable in the current binary bridge."
        )
        #endif
    }

    static func destroySession(_ session: BridgeSessionHandle?) {
        guard let session else {
            return
        }

        libtorrent_apple_session_destroy(session)
    }

    static func addMagnet(
        session: BridgeSessionHandle,
        magnetURI: String,
        downloadPath: String
    ) throws -> TorrentID {
        var nativeError = libtorrent_apple_error_t()
        var infoHashBuffer = [CChar](repeating: 0, count: Int(LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE))

        let succeeded = magnetURI.withCString { magnetURI in
            downloadPath.withCString { downloadPath in
                infoHashBuffer.withUnsafeMutableBufferPointer { infoHashBuffer in
                    libtorrent_apple_session_add_magnet(
                        session,
                        magnetURI,
                        downloadPath,
                        infoHashBuffer.baseAddress,
                        infoHashBuffer.count,
                        &nativeError
                    )
                }
            }
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to add magnet torrent.")
        }

        return TorrentID(rawValue: decodeCString(infoHashBuffer))
    }

    static func addTorrentFile(
        session: BridgeSessionHandle,
        torrentFilePath: String,
        downloadPath: String
    ) throws -> TorrentID {
        var nativeError = libtorrent_apple_error_t()
        var infoHashBuffer = [CChar](repeating: 0, count: Int(LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE))

        let succeeded = torrentFilePath.withCString { torrentFilePath in
            downloadPath.withCString { downloadPath in
                infoHashBuffer.withUnsafeMutableBufferPointer { infoHashBuffer in
                    libtorrent_apple_session_add_torrent_file(
                        session,
                        torrentFilePath,
                        downloadPath,
                        infoHashBuffer.baseAddress,
                        infoHashBuffer.count,
                        &nativeError
                    )
                }
            }
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to add .torrent file.")
        }

        return TorrentID(rawValue: decodeCString(infoHashBuffer))
    }

    static func addResumeData(
        session: BridgeSessionHandle,
        resumeData: Data,
        downloadPath: String
    ) throws -> TorrentID {
        var nativeError = libtorrent_apple_error_t()
        var infoHashBuffer = [CChar](repeating: 0, count: Int(LIBTORRENT_APPLE_INFO_HASH_HEX_SIZE))

        let succeeded = resumeData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }

            return downloadPath.withCString { downloadPath in
                infoHashBuffer.withUnsafeMutableBufferPointer { infoHashBuffer in
                    libtorrent_apple_session_add_resume_data(
                        session,
                        baseAddress,
                        rawBuffer.count,
                        downloadPath,
                        infoHashBuffer.baseAddress,
                        infoHashBuffer.count,
                        &nativeError
                    )
                }
            }
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to add native resume data.")
        }

        return TorrentID(rawValue: decodeCString(infoHashBuffer))
    }

    static func pauseTorrent(session: BridgeSessionHandle, id: TorrentID) throws {
        try perform(session: session, id: id, fallbackMessage: "Failed to pause torrent.") {
            libtorrent_apple_session_pause_torrent($0, $1, $2)
        }
    }

    static func resumeTorrent(session: BridgeSessionHandle, id: TorrentID) throws {
        try perform(session: session, id: id, fallbackMessage: "Failed to resume torrent.") {
            libtorrent_apple_session_resume_torrent($0, $1, $2)
        }
    }

    static func removeTorrent(session: BridgeSessionHandle, id: TorrentID, deleteData: Bool) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_session_remove_torrent(session, infoHash, deleteData, &nativeError)
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to remove torrent.")
        }
    }

    static func status(session: BridgeSessionHandle, id: TorrentID) throws -> libtorrent_apple_torrent_status_t {
        var nativeStatus = libtorrent_apple_torrent_status_t()
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_session_get_torrent_status(session, infoHash, &nativeStatus, &nativeError)
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to fetch torrent status.")
        }

        return nativeStatus
    }

    static func sessionStats(session: BridgeSessionHandle) throws -> BridgeNativeSessionStats {
        #if canImport(LibtorrentAppleBridge) || canImport(LibtorrentAppleBinary)
        var nativeStats = libtorrent_apple_session_stats_t()
        var nativeError = libtorrent_apple_error_t()

        guard libtorrent_apple_session_get_stats(session, &nativeStats, &nativeError) else {
            throw error(from: nativeError, fallbackMessage: "Failed to fetch session diagnostics.")
        }

        return BridgeNativeSessionStats(
            downloadRateBytesPerSecond: Int64(nativeStats.download_rate),
            uploadRateBytesPerSecond: Int64(nativeStats.upload_rate),
            totalConnections: Int(nativeStats.total_connections),
            totalPeers: Int(nativeStats.total_peers),
            totalSeeds: Int(nativeStats.total_seeds),
            isDHTEnabled: nativeStats.dht_enabled,
            dhtNodeCount: Int(nativeStats.dht_node_count)
        )
        #else
        throw LibtorrentAppleError.nativeOperationFailed(
            -1,
            "Session diagnostics are unavailable in the current binary bridge."
        )
        #endif
    }

    static func popAlert(session: BridgeSessionHandle) throws -> BridgeNativeAlert? {
        var nativeAlert = libtorrent_apple_alert_t()
        var nativeError = libtorrent_apple_error_t()

        guard libtorrent_apple_session_pop_alert(session, &nativeAlert, &nativeError) else {
            throw error(from: nativeError, fallbackMessage: "Failed to pop native alert.")
        }

        guard nativeAlert.has_alert else {
            return nil
        }

        let infoHash = decodeCString(nativeAlert.info_hash)
        let torrentID = infoHash.isEmpty ? nil : TorrentID(rawValue: infoHash)

        return BridgeNativeAlert(
            typeCode: nativeAlert.type_code,
            name: decodeCString(nativeAlert.name),
            message: decodeCString(nativeAlert.message),
            torrentID: torrentID
        )
    }

    static func exportNativeResumeData(session: BridgeSessionHandle, id: TorrentID) throws -> Data {
        try exportDataBuffer(
            session: session,
            id: id,
            fallbackMessage: "Failed to export native resume data.",
            operation: { libtorrent_apple_torrent_export_resume_data($0, $1, $2, $3) }
        )
    }

    static func exportTorrentFile(session: BridgeSessionHandle, id: TorrentID) throws -> Data {
        try exportDataBuffer(
            session: session,
            id: id,
            fallbackMessage: "Failed to export torrent file metadata.",
            operation: { libtorrent_apple_torrent_export_torrent_file($0, $1, $2, $3) }
        )
    }

    static func files(session: BridgeSessionHandle, id: TorrentID) throws -> [BridgeNativeTorrentFile] {
        var nativeCount = 0
        var nativeError = libtorrent_apple_error_t()

        let countSucceeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_file_count(session, infoHash, &nativeCount, &nativeError)
        }

        guard countSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to determine torrent file count.")
        }

        guard nativeCount > 0 else {
            return []
        }

        var nativeFiles = Array(
            repeating: libtorrent_apple_torrent_file_t(),
            count: nativeCount
        )
        var writtenCount = 0
        nativeError = libtorrent_apple_error_t()

        let listSucceeded = id.rawValue.withCString { infoHash in
            nativeFiles.withUnsafeMutableBufferPointer { buffer in
                libtorrent_apple_torrent_get_files(
                    session,
                    infoHash,
                    buffer.baseAddress,
                    buffer.count,
                    &writtenCount,
                    &nativeError
                )
            }
        }

        guard listSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to list torrent files.")
        }

        return nativeFiles.prefix(writtenCount).map { nativeFile in
            BridgeNativeTorrentFile(
                index: Int(nativeFile.index),
                name: decodeCString(nativeFile.name),
                path: decodeCString(nativeFile.path),
                sizeBytes: nativeFile.size,
                downloadedBytes: nativeFile.downloaded,
                priority: priority(from: nativeFile.priority)
            )
        }
    }

    static func setFilePriority(
        session: BridgeSessionHandle,
        id: TorrentID,
        fileIndex: Int,
        priority: TorrentDownloadPriority
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_set_file_priority(
                session,
                infoHash,
                Int32(clamping: fileIndex),
                Int32(priority.rawValue),
                &nativeError
            )
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to change torrent file priority.")
        }
    }

    static func setSequentialDownload(
        session: BridgeSessionHandle,
        id: TorrentID,
        isEnabled: Bool
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_set_sequential_download(session, infoHash, isEnabled, &nativeError)
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to update sequential download mode.")
        }
    }

    static func forceRecheck(session: BridgeSessionHandle, id: TorrentID) throws {
        try perform(
            session: session,
            id: id,
            fallbackMessage: "Failed to force torrent recheck.",
            operation: { libtorrent_apple_torrent_force_recheck($0, $1, $2) }
        )
    }

    static func forceReannounce(
        session: BridgeSessionHandle,
        id: TorrentID,
        after seconds: Int,
        trackerIndex: Int?,
        ignoreMinimumInterval: Bool
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_force_reannounce(
                session,
                infoHash,
                Int32(clamping: seconds),
                Int32(clamping: trackerIndex ?? -1),
                ignoreMinimumInterval,
                &nativeError
            )
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to force tracker reannounce.")
        }
    }

    static func moveStorage(
        session: BridgeSessionHandle,
        id: TorrentID,
        downloadPath: String,
        strategy: TorrentStorageMoveStrategy
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            downloadPath.withCString { downloadPath in
                libtorrent_apple_torrent_move_storage(
                    session,
                    infoHash,
                    downloadPath,
                    strategy.rawValue,
                    &nativeError
                )
            }
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to move torrent storage.")
        }
    }

    static func piecePriorities(session: BridgeSessionHandle, id: TorrentID) throws -> [TorrentDownloadPriority] {
        var nativeCount = 0
        var nativeError = libtorrent_apple_error_t()

        let countSucceeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_piece_count(session, infoHash, &nativeCount, &nativeError)
        }

        guard countSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to determine torrent piece count.")
        }

        guard nativeCount > 0 else {
            return []
        }

        var nativePriorities = Array(repeating: UInt8(0), count: nativeCount)
        var writtenCount = 0
        nativeError = libtorrent_apple_error_t()

        let listSucceeded = id.rawValue.withCString { infoHash in
            nativePriorities.withUnsafeMutableBufferPointer { buffer in
                libtorrent_apple_torrent_get_piece_priorities(
                    session,
                    infoHash,
                    buffer.baseAddress,
                    buffer.count,
                    &writtenCount,
                    &nativeError
                )
            }
        }

        guard listSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to fetch torrent piece priorities.")
        }

        return nativePriorities.prefix(writtenCount).map { priority(from: Int32($0)) }
    }

    static func setPiecePriority(
        session: BridgeSessionHandle,
        id: TorrentID,
        pieceIndex: Int,
        priority: TorrentDownloadPriority
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_set_piece_priority(
                session,
                infoHash,
                Int32(clamping: pieceIndex),
                Int32(priority.rawValue),
                &nativeError
            )
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to change torrent piece priority.")
        }
    }

    static func setPieceDeadline(
        session: BridgeSessionHandle,
        id: TorrentID,
        pieceIndex: Int,
        milliseconds: Int
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_set_piece_deadline(
                session,
                infoHash,
                Int32(clamping: pieceIndex),
                Int32(clamping: milliseconds),
                &nativeError
            )
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to set torrent piece deadline.")
        }
    }

    static func resetPieceDeadline(
        session: BridgeSessionHandle,
        id: TorrentID,
        pieceIndex: Int
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_reset_piece_deadline(
                session,
                infoHash,
                Int32(clamping: pieceIndex),
                &nativeError
            )
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to clear torrent piece deadline.")
        }
    }

    static func trackers(session: BridgeSessionHandle, id: TorrentID) throws -> [BridgeNativeTorrentTracker] {
        var nativeCount = 0
        var nativeError = libtorrent_apple_error_t()

        let countSucceeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_tracker_count(session, infoHash, &nativeCount, &nativeError)
        }

        guard countSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to determine torrent tracker count.")
        }

        guard nativeCount > 0 else {
            return []
        }

        var capacity = max(nativeCount, 8)
        for _ in 0 ..< 4 {
            var nativeTrackers = Array(
                repeating: libtorrent_apple_torrent_tracker_t(),
                count: capacity
            )
            var writtenCount = 0
            nativeError = libtorrent_apple_error_t()

            let listSucceeded = id.rawValue.withCString { infoHash in
                nativeTrackers.withUnsafeMutableBufferPointer { buffer in
                    libtorrent_apple_torrent_get_trackers(
                        session,
                        infoHash,
                        buffer.baseAddress,
                        buffer.count,
                        &writtenCount,
                        &nativeError
                    )
                }
            }

            if listSucceeded {
                return nativeTrackers.prefix(writtenCount).map { nativeTracker in
                    let message = decodeCString(nativeTracker.message)
                    return BridgeNativeTorrentTracker(
                        url: decodeCString(nativeTracker.url),
                        tier: Int(nativeTracker.tier),
                        failureCount: Int(nativeTracker.fail_count),
                        sourceMask: Int(nativeTracker.source_mask),
                        isVerified: nativeTracker.verified,
                        message: message.isEmpty ? nil : message
                    )
                }
            }

            let resolvedError = error(from: nativeError, fallbackMessage: "Failed to fetch torrent trackers.")
            if case let .nativeOperationFailed(_, message) = resolvedError,
               message.localizedCaseInsensitiveContains("capacity"),
               message.localizedCaseInsensitiveContains("tracker")
            {
                capacity *= 2
                continue
            }

            throw resolvedError
        }

        throw LibtorrentAppleError.trackerOperationFailed("Failed to fetch torrent trackers after retrying tracker capacity.")
    }

    static func replaceTrackers(
        session: BridgeSessionHandle,
        id: TorrentID,
        trackers: [TorrentTrackerUpdate]
    ) throws {
        var nativeError = libtorrent_apple_error_t()
        var nativeTrackers = trackers.map { tracker -> libtorrent_apple_torrent_tracker_update_t in
            var nativeTracker = libtorrent_apple_torrent_tracker_update_t()
            nativeTracker.tier = Int32(clamping: tracker.tier)
            encodeCString(tracker.url, into: &nativeTracker.url)
            return nativeTracker
        }

        let succeeded = id.rawValue.withCString { infoHash in
            nativeTrackers.withUnsafeMutableBufferPointer { buffer in
                libtorrent_apple_torrent_replace_trackers(
                    session,
                    infoHash,
                    buffer.baseAddress,
                    buffer.count,
                    &nativeError
                )
            }
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to replace torrent trackers.")
        }
    }

    static func addTracker(
        session: BridgeSessionHandle,
        id: TorrentID,
        tracker: TorrentTrackerUpdate
    ) throws {
        try addTrackers(
            session: session,
            id: id,
            trackers: [tracker],
            forceReannounce: true
        )
    }

    static func addTrackers(
        session: BridgeSessionHandle,
        id: TorrentID,
        trackers: [TorrentTrackerUpdate],
        forceReannounce: Bool
    ) throws {
        guard !trackers.isEmpty else {
            return
        }

        var nativeTrackers = trackers.map { tracker -> libtorrent_apple_torrent_tracker_update_t in
            var nativeTracker = libtorrent_apple_torrent_tracker_update_t()
            nativeTracker.tier = Int32(clamping: tracker.tier)
            encodeCString(tracker.url, into: &nativeTracker.url)
            return nativeTracker
        }

        var nativeError = libtorrent_apple_error_t()

        #if canImport(LibtorrentAppleBridge) || canImport(LibtorrentAppleBinary)
        let succeeded = id.rawValue.withCString { infoHash in
            nativeTrackers.withUnsafeMutableBufferPointer { buffer in
                libtorrent_apple_torrent_add_trackers(
                    session,
                    infoHash,
                    buffer.baseAddress,
                    buffer.count,
                    forceReannounce,
                    &nativeError
                )
            }
        }
        #else
        guard forceReannounce else {
            throw LibtorrentAppleError.nativeOperationFailed(
                -1,
                "Batch tracker add without reannounce is unavailable in the current binary bridge."
            )
        }

        let succeeded = id.rawValue.withCString { infoHash in
            nativeTrackers.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices {
                    var nativeTracker = buffer[index]
                    guard libtorrent_apple_torrent_add_tracker(session, infoHash, &nativeTracker, &nativeError) else {
                        return false
                    }
                }
                return true
            }
        }
        #endif

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to add torrent trackers.")
        }
    }

    static func peers(session: BridgeSessionHandle, id: TorrentID) throws -> [BridgeNativeTorrentPeer] {
        var nativeCount = 0
        var nativeError = libtorrent_apple_error_t()

        let countSucceeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_peer_count(session, infoHash, &nativeCount, &nativeError)
        }

        guard countSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to determine torrent peer count.")
        }

        guard nativeCount > 0 else {
            return []
        }

        var nativePeers = Array(
            repeating: libtorrent_apple_torrent_peer_t(),
            count: nativeCount
        )
        var writtenCount = 0
        nativeError = libtorrent_apple_error_t()

        let listSucceeded = id.rawValue.withCString { infoHash in
            nativePeers.withUnsafeMutableBufferPointer { buffer in
                libtorrent_apple_torrent_get_peers(
                    session,
                    infoHash,
                    buffer.baseAddress,
                    buffer.count,
                    &writtenCount,
                    &nativeError
                )
            }
        }

        guard listSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to fetch torrent peers.")
        }

        return nativePeers.prefix(writtenCount).map { nativePeer in
            BridgeNativeTorrentPeer(
                endpoint: decodeCString(nativePeer.endpoint),
                client: decodeCString(nativePeer.client),
                flags: Int(nativePeer.flags),
                sourceMask: Int(nativePeer.source_mask),
                downloadRateBytesPerSecond: Int64(nativePeer.download_rate),
                uploadRateBytesPerSecond: Int64(nativePeer.upload_rate),
                queueBytes: Int(nativePeer.queue_bytes),
                totalDownloadedBytes: nativePeer.total_download,
                totalUploadedBytes: nativePeer.total_upload,
                progress: nativePeer.progress,
                isSeed: nativePeer.is_seed
            )
        }
    }

    static func pieces(session: BridgeSessionHandle, id: TorrentID) throws -> [BridgeNativeTorrentPiece] {
        var nativeCount = 0
        var nativeError = libtorrent_apple_error_t()

        let countSucceeded = id.rawValue.withCString { infoHash in
            libtorrent_apple_torrent_piece_count(session, infoHash, &nativeCount, &nativeError)
        }

        guard countSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to determine torrent piece count.")
        }

        guard nativeCount > 0 else {
            return []
        }

        var nativePieces = Array(
            repeating: libtorrent_apple_torrent_piece_t(),
            count: nativeCount
        )
        var writtenCount = 0
        nativeError = libtorrent_apple_error_t()

        let listSucceeded = id.rawValue.withCString { infoHash in
            nativePieces.withUnsafeMutableBufferPointer { buffer in
                libtorrent_apple_torrent_get_pieces(
                    session,
                    infoHash,
                    buffer.baseAddress,
                    buffer.count,
                    &writtenCount,
                    &nativeError
                )
            }
        }

        guard listSucceeded else {
            throw error(from: nativeError, fallbackMessage: "Failed to fetch torrent pieces.")
        }

        return nativePieces.prefix(writtenCount).map { nativePiece in
            BridgeNativeTorrentPiece(
                index: Int(nativePiece.index),
                priority: priority(from: nativePiece.priority),
                availability: Int(nativePiece.availability),
                isDownloaded: nativePiece.downloaded
            )
        }
    }

    private static func exportDataBuffer(
        session: BridgeSessionHandle,
        id: TorrentID,
        fallbackMessage: String,
        operation: (BridgeSessionHandle, UnsafePointer<CChar>, UnsafeMutablePointer<libtorrent_apple_byte_buffer_t>, UnsafeMutablePointer<libtorrent_apple_error_t>) -> Bool
    ) throws -> Data {
        var nativeBuffer = libtorrent_apple_byte_buffer_t()
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            operation(session, infoHash, &nativeBuffer, &nativeError)
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: fallbackMessage)
        }

        defer {
            libtorrent_apple_byte_buffer_free(&nativeBuffer)
        }

        guard let baseAddress = nativeBuffer.data else {
            throw LibtorrentAppleError.nativeOperationFailed(-1, "Native bridge returned an empty resume data buffer.")
        }

        return Data(bytes: baseAddress, count: nativeBuffer.size)
    }

    static func state(from nativeStatus: libtorrent_apple_torrent_status_t) -> TorrentState {
        if nativeStatus.paused {
            return .paused
        }

        switch decodeCString(nativeStatus.state).lowercased() {
        case "finished", "seeding", "downloading":
            return .running
        case "checking_files", "checking_resume_data", "downloading_metadata":
            return .idle
        default:
            return .running
        }
    }

    static func metrics(from nativeStatus: libtorrent_apple_torrent_status_t) -> TorrentMetrics {
        let listPeerCount = Int(nativeStatus.list_peers)
        let listSeedCount = Int(nativeStatus.list_seeds)
        let peerTotal = resolvedSwarmTotal(
            primary: Int(nativeStatus.num_incomplete),
            fallbackEstimate: listPeerCount
        )
        let seedTotal = resolvedSwarmTotal(
            primary: Int(nativeStatus.num_complete),
            fallbackEstimate: listSeedCount
        )

        return TorrentMetrics(
            progress: nativeStatus.progress,
            downloadedBytes: nativeStatus.total_download,
            uploadedBytes: nativeStatus.total_upload,
            totalSizeBytes: nativeStatus.total_size,
            downloadRateBytesPerSecond: Int64(nativeStatus.download_rate),
            uploadRateBytesPerSecond: Int64(nativeStatus.upload_rate),
            peerCount: Int(nativeStatus.num_peers),
            seedCount: Int(nativeStatus.num_seeds),
            peerTotalCount: peerTotal,
            seedTotalCount: seedTotal,
            peerListCount: max(listPeerCount, 0),
            seedListCount: max(listSeedCount, 0)
        )
    }

    static func nativeName(from nativeStatus: libtorrent_apple_torrent_status_t) -> String? {
        let name = decodeCString(nativeStatus.name)
        return name.isEmpty ? nil : name
    }

    static func error(from nativeError: libtorrent_apple_error_t, fallbackMessage: String) -> LibtorrentAppleError {
        let message = decodeCString(nativeError.message)
        let resolvedMessage = message.isEmpty ? fallbackMessage : message
        return .nativeOperationFailed(nativeError.code, resolvedMessage)
    }

    static func priority(from nativePriority: Int32) -> TorrentDownloadPriority {
        TorrentDownloadPriority(rawValue: UInt8(clamping: nativePriority)) ?? .default
    }

    private static func resolvedSwarmTotal(primary: Int, fallbackEstimate: Int) -> Int? {
        if primary >= 0 {
            return primary
        }
        if fallbackEstimate > 0 {
            return fallbackEstimate
        }
        return nil
    }

    private static func perform(
        session: BridgeSessionHandle,
        id: TorrentID,
        fallbackMessage: String,
        operation: (BridgeSessionHandle, UnsafePointer<CChar>, UnsafeMutablePointer<libtorrent_apple_error_t>) -> Bool
    ) throws {
        var nativeError = libtorrent_apple_error_t()

        let succeeded = id.rawValue.withCString { infoHash in
            operation(session, infoHash, &nativeError)
        }

        guard succeeded else {
            throw error(from: nativeError, fallbackMessage: fallbackMessage)
        }
    }

    private static func makeNativeSessionConfiguration(
        from configuration: SessionConfiguration
    ) -> libtorrent_apple_session_configuration_t {
        var nativeConfiguration = libtorrent_apple_session_configuration_default()
        nativeConfiguration.enable_dht = configuration.enableDistributedHashTable
        nativeConfiguration.enable_lsd = configuration.enableLocalPeerDiscovery
        nativeConfiguration.enable_upnp = configuration.enableUPnP
        nativeConfiguration.enable_natpmp = configuration.enableNATPMP
        nativeConfiguration.listen_port = listenPort(from: configuration)
        nativeConfiguration.alert_mask = configuration.alertMask ?? LIBTORRENT_APPLE_DEFAULT_ALERT_MASK
        nativeConfiguration.upload_rate_limit = Int32(clamping: configuration.uploadRateLimitBytesPerSecond)
        nativeConfiguration.download_rate_limit = Int32(clamping: configuration.downloadRateLimitBytesPerSecond)
        nativeConfiguration.connections_limit = Int32(clamping: configuration.connectionsLimit)
        nativeConfiguration.active_downloads_limit = Int32(clamping: configuration.activeDownloadsLimit)
        nativeConfiguration.active_seeds_limit = Int32(clamping: configuration.activeSeedsLimit)
        nativeConfiguration.active_checking_limit = Int32(clamping: configuration.activeCheckingLimit)
        nativeConfiguration.active_dht_limit = Int32(clamping: configuration.activeDistributedHashTableLimit)
        nativeConfiguration.active_tracker_limit = Int32(clamping: configuration.activeTrackerLimit)
        nativeConfiguration.active_lsd_limit = Int32(clamping: configuration.activeLocalPeerDiscoveryLimit)
        nativeConfiguration.active_limit = Int32(clamping: configuration.activeTorrentLimit)
        nativeConfiguration.max_queued_disk_bytes = Int32(clamping: configuration.maxQueuedDiskBytes)
        nativeConfiguration.send_buffer_low_watermark = Int32(clamping: configuration.sendBufferLowWatermarkBytes)
        nativeConfiguration.send_buffer_watermark = Int32(clamping: configuration.sendBufferWatermarkBytes)
        nativeConfiguration.send_buffer_watermark_factor = Int32(clamping: configuration.sendBufferWatermarkFactorPercent)
        nativeConfiguration.out_enc_policy = configuration.encryption.outgoingPolicy.rawValue
        nativeConfiguration.in_enc_policy = configuration.encryption.incomingPolicy.rawValue
        nativeConfiguration.allowed_enc_level = configuration.encryption.allowedLevel.rawValue
        nativeConfiguration.prefer_rc4 = configuration.encryption.preferRC4
        nativeConfiguration.auto_sequential = configuration.autoSequentialDownload
        encodeCString(configuration.userAgent, into: &nativeConfiguration.user_agent)
        encodeCString(configuration.handshakeClientVersion ?? "", into: &nativeConfiguration.handshake_client_version)
        encodeCString(configuration.listenInterfaces.joined(separator: ","), into: &nativeConfiguration.listen_interfaces)

        #if canImport(LibtorrentAppleBridge) || canImport(LibtorrentAppleBinary)
        nativeConfiguration.share_ratio_limit = Int32(clamping: configuration.shareRatioLimit)
        encodeCString(configuration.peerFingerprint ?? "", into: &nativeConfiguration.peer_fingerprint)
        encodeCString(configuration.dhtBootstrapNodes.joined(separator: ","), into: &nativeConfiguration.dht_bootstrap_nodes)
        encodeCString(configuration.peerBlockedCIDRs.joined(separator: ","), into: &nativeConfiguration.peer_blocked_cidrs)
        encodeCString(configuration.peerAllowedCIDRs.joined(separator: ","), into: &nativeConfiguration.peer_allowed_cidrs)
        #endif

        if let proxy = configuration.proxy {
            nativeConfiguration.proxy_type = proxy.type.rawValue
            nativeConfiguration.proxy_port = Int32(clamping: proxy.port)
            nativeConfiguration.proxy_hostnames = proxy.proxyHostnames
            nativeConfiguration.proxy_peer_connections = proxy.proxyPeerConnections
            nativeConfiguration.proxy_tracker_connections = proxy.proxyTrackerConnections
            encodeCString(proxy.hostname, into: &nativeConfiguration.proxy_hostname)
            encodeCString(proxy.username ?? "", into: &nativeConfiguration.proxy_username)
            encodeCString(proxy.password ?? "", into: &nativeConfiguration.proxy_password)
        } else {
            nativeConfiguration.proxy_type = SessionProxyConfiguration.ProxyType.none.rawValue
        }

        return nativeConfiguration
    }

    private static func listenPort(from configuration: SessionConfiguration) -> Int32 {
        for interface in configuration.listenInterfaces {
            guard let portText = interface.split(separator: ":").last,
                  let port = Int32(portText)
            else {
                continue
            }

            return max(port, 0)
        }

        return 0
    }

    private static func encodeCString<T>(_ value: String, into field: inout T) {
        withUnsafeMutableBytes(of: &field) { rawBuffer in
            guard !rawBuffer.isEmpty else {
                return
            }

            var encoded = [UInt8](repeating: 0, count: rawBuffer.count)
            let truncatedBytes = value.utf8.prefix(max(rawBuffer.count - 1, 0))
            for (index, byte) in truncatedBytes.enumerated() {
                encoded[index] = byte
            }

            rawBuffer.copyBytes(from: encoded)
        }
    }

    private static func decodeCString(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decodeCString<T>(_ tuple: T) -> String {
        withUnsafePointer(to: tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { cStringPointer in
                String(cString: cStringPointer)
            }
        }
    }
}
