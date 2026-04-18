import Foundation

import LibtorrentApple

let downloadDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("libtorrent-apple-version-switch-consumer", isDirectory: true)

try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)

let session = TorrentSession(
    configuration: SessionConfiguration(
        downloadDirectory: downloadDirectory,
        validateHTTPSTrackers: true
    )
)

_ = LibtorrentApple.backendInfo

try await session.start()
let diagnostics = try await session.sessionDiagnostics()
let reopenedSockets = try await session.reopenNetworkSockets(remapPorts: false)

print(
    """
    bridgeVersion=\(LibtorrentApple.bridgeVersion)
    httpsTrackers=\(LibtorrentApple.backendSupportsHTTPSTrackers)
    isListening=\(diagnostics.isListening ?? false)
    reopenedSockets=\(reopenedSockets)
    """
)

await session.stop()
