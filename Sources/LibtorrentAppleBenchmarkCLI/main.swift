import Foundation
import LibtorrentApple

private struct CLIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private enum BenchmarkProfile: String, CaseIterable, Codable {
    case baseline
    case animekoParity = "animeko-parity"

    var defaultConnectionsLimit: Int? {
        switch self {
        case .baseline:
            return nil
        case .animekoParity:
            return 200
        }
    }

    var defaultDHTBootstrapNodes: [String] {
        switch self {
        case .baseline:
            return []
        case .animekoParity:
            return [
                "router.utorrent.com:6881",
                "router.bittorrent.com:6881",
                "dht.transmissionbt.com:6881",
                "router.bitcomet.com:6881",
            ]
        }
    }

    var defaultTrackerURLs: [String] {
        switch self {
        case .baseline:
            return []
        case .animekoParity:
            return [
                "udp://tracker1.itzmx.com:8080/announce",
                "udp://moonburrow.club:6969/announce",
                "udp://new-line.net:6969/announce",
                "udp://opentracker.io:6969/announce",
                "udp://tamas3.ynh.fr:6969/announce",
                "udp://tracker.bittor.pw:1337/announce",
                "udp://tracker.dump.cl:6969/announce",
                "udp://tracker2.dler.org:80/announce",
                "https://tracker.tamersunion.org:443/announce",
                "udp://open.demonii.com:1337/announce",
                "udp://open.stealth.si:80/announce",
                "udp://tracker.torrent.eu.org:451/announce",
                "udp://exodus.desync.com:6969/announce",
                "udp://tracker.moeking.me:6969/announce",
                "udp://tracker1.bt.moack.co.kr:80/announce",
                "udp://tracker.tiny-vps.com:6969/announce",
                "udp://bt1.archive.org:6969/announce",
                "udp://tracker.opentrackr.org:1337/announce",
                "http://tracker.opentrackr.org:1337/announce",
                "https://tracker1.520.jp:443/announce",
            ]
        }
    }
}

private enum SourceKind: String, Codable {
    case magnet
    case file
}

private struct SourceInput: Codable {
    let kind: SourceKind
    let value: String
    let displayName: String?
}

private struct TrackerInjectionReport: Codable {
    let torrentID: String
    let requestedTrackers: Int
    let resultingTrackers: Int?
    let error: String?
}

private struct SessionSample: Codable {
    let timestamp: String
    let downloadRateBytesPerSecond: Int64
    let uploadRateBytesPerSecond: Int64
    let totalConnections: Int
    let totalPeers: Int
    let totalSeeds: Int
    let isDHTEnabled: Bool
    let dhtNodeCount: Int
}

private struct TorrentSample: Codable {
    let timestamp: String
    let torrentID: String
    let progress: Double
    let downloadRateBytesPerSecond: Int64
    let uploadRateBytesPerSecond: Int64
    let peers: Int
    let seeds: Int
    let totalDownloadBytes: Int64
    let totalUploadBytes: Int64
}

private struct ConfigurationSnapshot: Codable {
    let profile: BenchmarkProfile
    let userAgent: String
    let handshakeClientVersion: String?
    let peerFingerprint: String?
    let connectionsLimit: Int
    let dhtBootstrapNodes: [String]
    let trackerPresetCount: Int
}

private struct BackendSnapshot: Codable {
    let packageMode: String
    let vendor: String
    let libraryVersion: String
    let bridgeVersion: String
    let packageName: String
    let isPlaceholderBridge: Bool
}

private struct BenchmarkSummary: Codable {
    let startedAt: String
    let endedAt: String
    let samplingDurationSeconds: Int
    let sampleIntervalSeconds: Int
    let sourceCount: Int
    let addedTorrentCount: Int
    let profile: BenchmarkProfile
    let backend: BackendSnapshot
    let configuration: ConfigurationSnapshot
    let trackerInjectionReports: [TrackerInjectionReport]
    let averageDownloadRateBytesPerSecond: Double
    let averageUploadRateBytesPerSecond: Double
    let p95DownloadRateBytesPerSecond: Int64
    let p95UploadRateBytesPerSecond: Int64
    let averageConnections: Double
    let averagePeers: Double
    let averageSeeds: Double
    let averageDHTNodeCount: Double
    let sessionSampleCount: Int
    let torrentSampleCount: Int
    let warnings: [String]
}

private struct BenchmarkArchive: Codable {
    let summary: BenchmarkSummary
    let sessionSamples: [SessionSample]
    let torrentSamples: [TorrentSample]
}

private struct CLIOptions {
    let profile: BenchmarkProfile
    let durationSeconds: Int
    let intervalSeconds: Int
    let outputDirectory: URL
    let rootDirectory: URL?
    let sourceInputs: [SourceInput]
    let trackerURLs: [String]
    let disableProfileTrackers: Bool
    let connectionsLimitOverride: Int?
    let dhtBootstrapNodeOverrides: [String]
    let userAgentOverride: String?
    let handshakeClientVersionOverride: String?
    let peerFingerprintOverride: String?

    static var usage: String {
        """
        Usage:
          swift run LibtorrentAppleBenchmarkCLI [options]

        Required input (at least one source):
          --magnet <uri>             Add a magnet source. Repeatable.
          --torrent-file <path>      Add a local .torrent source. Repeatable.
          --sources-file <path>      Load sources from file. Repeatable.

        Optional:
          --profile <name>           baseline | animeko-parity (default: baseline)
          --duration <seconds>       Sampling window in seconds (default: 300)
          --interval <seconds>       Sampling interval in seconds (default: 1)
          --output-dir <path>        Output directory for CSV/JSON logs
          --root-dir <path>          Downloader root directory
          --tracker <url>            Tracker URL to inject after add. Repeatable.
          --tracker-file <path>      Load tracker URLs from file. Repeatable.
          --disable-profile-trackers Disable profile default tracker preset
          --connections-limit <n>    Override connections limit
          --dht-bootstrap <node>     Override/add bootstrap node. Repeatable.
          --user-agent <value>       Override user agent
          --handshake-version <val>  Override handshake client version
          --peer-fingerprint <val>   Override peer fingerprint
          --help                     Show this help

        Sources file format:
          - magnet|<magnet-uri>|<optional-display-name>
          - file|<path-to-torrent>|<optional-display-name>
          - or simple lines:
            magnet:?xt=...
            /absolute/or/relative/path/to/file.torrent
        """
    }

    static func parse(arguments: [String]) throws -> CLIOptions {
        var profile: BenchmarkProfile = .baseline
        var durationSeconds = 300
        var intervalSeconds = 1
        var outputDirectory: URL?
        var rootDirectory: URL?
        var sourceInputs: [SourceInput] = []
        var trackerURLs: [String] = []
        var disableProfileTrackers = false
        var connectionsLimitOverride: Int?
        var dhtBootstrapNodeOverrides: [String] = []
        var userAgentOverride: String?
        var handshakeClientVersionOverride: String?
        var peerFingerprintOverride: String?

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            func requireValue(_ flag: String) throws -> String {
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError(message: "Missing value for \(flag).")
                }
                index = nextIndex
                return arguments[nextIndex]
            }

            switch argument {
            case "--help", "-h":
                throw CLIError(message: CLIOptions.usage)
            case "--profile":
                let value = try requireValue(argument)
                guard let parsed = BenchmarkProfile(rawValue: value) else {
                    let supported = BenchmarkProfile.allCases.map(\.rawValue).joined(separator: ", ")
                    throw CLIError(message: "Unsupported profile '\(value)'. Supported: \(supported)")
                }
                profile = parsed
            case "--duration":
                let value = try requireValue(argument)
                guard let parsed = Int(value), parsed > 0 else {
                    throw CLIError(message: "--duration must be a positive integer.")
                }
                durationSeconds = parsed
            case "--interval":
                let value = try requireValue(argument)
                guard let parsed = Int(value), parsed > 0 else {
                    throw CLIError(message: "--interval must be a positive integer.")
                }
                intervalSeconds = parsed
            case "--output-dir":
                let value = try requireValue(argument)
                outputDirectory = resolvePath(value, relativeTo: currentDirectory)
            case "--root-dir":
                let value = try requireValue(argument)
                rootDirectory = resolvePath(value, relativeTo: currentDirectory)
            case "--magnet":
                let value = try requireValue(argument)
                sourceInputs.append(SourceInput(kind: .magnet, value: value, displayName: nil))
            case "--torrent-file":
                let value = try requireValue(argument)
                let resolved = resolvePath(value, relativeTo: currentDirectory)
                sourceInputs.append(SourceInput(kind: .file, value: resolved.path, displayName: nil))
            case "--sources-file":
                let value = try requireValue(argument)
                let sourcesFileURL = resolvePath(value, relativeTo: currentDirectory)
                sourceInputs.append(contentsOf: try parseSourcesFile(at: sourcesFileURL))
            case "--tracker":
                let value = try requireValue(argument).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    trackerURLs.append(value)
                }
            case "--tracker-file":
                let value = try requireValue(argument)
                let trackerFileURL = resolvePath(value, relativeTo: currentDirectory)
                trackerURLs.append(contentsOf: try parseTrackersFile(at: trackerFileURL))
            case "--disable-profile-trackers":
                disableProfileTrackers = true
            case "--connections-limit":
                let value = try requireValue(argument)
                guard let parsed = Int(value), parsed >= 0 else {
                    throw CLIError(message: "--connections-limit must be a non-negative integer.")
                }
                connectionsLimitOverride = parsed
            case "--dht-bootstrap":
                let value = try requireValue(argument).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    dhtBootstrapNodeOverrides.append(value)
                }
            case "--user-agent":
                userAgentOverride = try requireValue(argument)
            case "--handshake-version":
                handshakeClientVersionOverride = try requireValue(argument)
            case "--peer-fingerprint":
                peerFingerprintOverride = try requireValue(argument)
            default:
                throw CLIError(message: "Unknown option '\(argument)'.\n\n\(CLIOptions.usage)")
            }

            index += 1
        }

        guard !sourceInputs.isEmpty else {
            throw CLIError(message: "No torrent source provided.\n\n\(CLIOptions.usage)")
        }

        let deduplicatedTrackers = orderedUnique(trackerURLs)
        let deduplicatedDHTNodes = orderedUnique(dhtBootstrapNodeOverrides)

        let resolvedOutputDirectory: URL = {
            if let outputDirectory {
                return outputDirectory.standardizedFileURL
            }
            let runID = Int(Date().timeIntervalSince1970)
            return currentDirectory
                .appendingPathComponent("Build", isDirectory: true)
                .appendingPathComponent("benchmark", isDirectory: true)
                .appendingPathComponent("run-\(runID)", isDirectory: true)
                .standardizedFileURL
        }()

        return CLIOptions(
            profile: profile,
            durationSeconds: durationSeconds,
            intervalSeconds: intervalSeconds,
            outputDirectory: resolvedOutputDirectory,
            rootDirectory: rootDirectory?.standardizedFileURL,
            sourceInputs: sourceInputs,
            trackerURLs: deduplicatedTrackers,
            disableProfileTrackers: disableProfileTrackers,
            connectionsLimitOverride: connectionsLimitOverride,
            dhtBootstrapNodeOverrides: deduplicatedDHTNodes,
            userAgentOverride: userAgentOverride,
            handshakeClientVersionOverride: handshakeClientVersionOverride,
            peerFingerprintOverride: peerFingerprintOverride
        )
    }

    private static func parseSourcesFile(at fileURL: URL) throws -> [SourceInput] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let baseDirectory = fileURL.deletingLastPathComponent()
        var sources: [SourceInput] = []

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let components = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            if components.count >= 2 {
                let kindText = components[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let valueText = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = components.count == 3
                    ? components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""

                let resolvedDisplayName = displayName.isEmpty ? nil : displayName
                switch kindText {
                case "magnet":
                    sources.append(SourceInput(kind: .magnet, value: valueText, displayName: resolvedDisplayName))
                    continue
                case "file":
                    let resolved = resolvePath(valueText, relativeTo: baseDirectory)
                    sources.append(SourceInput(kind: .file, value: resolved.path, displayName: resolvedDisplayName))
                    continue
                default:
                    break
                }
            }

            if line.lowercased().hasPrefix("magnet:?") {
                sources.append(SourceInput(kind: .magnet, value: line, displayName: nil))
            } else {
                let resolved = resolvePath(line, relativeTo: baseDirectory)
                sources.append(SourceInput(kind: .file, value: resolved.path, displayName: nil))
            }

        }

        return sources
    }

    private static func parseTrackersFile(at fileURL: URL) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

@main
private enum LibtorrentAppleBenchmarkCLI {
    static func main() async {
        do {
            let options = try CLIOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            let resultDirectory = try await runBenchmark(using: options)
            print("Benchmark completed.")
            print("Output directory: \(resultDirectory.path)")
        } catch let error as CLIError {
            fputs("\(error.message)\n", stderr)
            if error.message != CLIOptions.usage {
                fputs("\n\(CLIOptions.usage)\n", stderr)
            }
            exit(2)
        } catch {
            fputs("Benchmark failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runBenchmark(using options: CLIOptions) async throws -> URL {
        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

        let rootDirectory =
            (options.rootDirectory
                ?? options.outputDirectory.appendingPathComponent("downloader-root", isDirectory: true))
            .standardizedFileURL
        let downloadDirectory = rootDirectory.appendingPathComponent("Downloads", isDirectory: true)

        var configuration = SessionConfiguration(downloadDirectory: downloadDirectory)
        if let connectionsLimit = options.connectionsLimitOverride ?? options.profile.defaultConnectionsLimit {
            configuration.connectionsLimit = connectionsLimit
        }

        let configuredDHTBootstrapNodes = options.dhtBootstrapNodeOverrides.isEmpty
            ? options.profile.defaultDHTBootstrapNodes
            : options.dhtBootstrapNodeOverrides
        configuration.dhtBootstrapNodes = orderedUnique(configuredDHTBootstrapNodes)

        if let userAgentOverride = options.userAgentOverride, !userAgentOverride.isEmpty {
            configuration.userAgent = userAgentOverride
        }
        configuration.handshakeClientVersion = options.handshakeClientVersionOverride ?? configuration.handshakeClientVersion
        configuration.peerFingerprint = options.peerFingerprintOverride ?? configuration.peerFingerprint

        let profileTrackers = options.disableProfileTrackers ? [] : options.profile.defaultTrackerURLs
        let injectedTrackers = orderedUnique(profileTrackers + options.trackerURLs)
        let trackerUpdates = injectedTrackers.enumerated().map { index, url in
            TorrentTrackerUpdate(url: url, tier: index)
        }

        let configurationSnapshot = ConfigurationSnapshot(
            profile: options.profile,
            userAgent: configuration.userAgent,
            handshakeClientVersion: configuration.handshakeClientVersion,
            peerFingerprint: configuration.peerFingerprint,
            connectionsLimit: configuration.connectionsLimit,
            dhtBootstrapNodes: configuration.dhtBootstrapNodes,
            trackerPresetCount: injectedTrackers.count
        )

        let downloader = TorrentDownloader(
            configuration: configuration,
            rootDirectory: rootDirectory
        )

        try await downloader.start()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        do {
            var handles: [TorrentHandle] = []
            var warnings: [String] = []

            for sourceInput in options.sourceInputs {
                let source = try makeTorrentSource(from: sourceInput)
                let handle = try await downloader.addTorrent(
                    from: source,
                    options: AddTorrentOptions(displayName: sourceInput.displayName)
                )
                handles.append(handle)
            }

            guard !handles.isEmpty else {
                throw CLIError(message: "No torrent was successfully added.")
            }

            var trackerReports: [TrackerInjectionReport] = []
            if !trackerUpdates.isEmpty {
                for handle in handles {
                    do {
                        let trackers = try await handle.addTrackers(trackerUpdates, forceReannounce: true)
                        trackerReports.append(
                            TrackerInjectionReport(
                                torrentID: handle.id.rawValue,
                                requestedTrackers: trackerUpdates.count,
                                resultingTrackers: trackers.count,
                                error: nil
                            )
                        )
                    } catch {
                        let message = "Tracker injection failed for \(handle.id.rawValue): \(error.localizedDescription)"
                        warnings.append(message)
                        trackerReports.append(
                            TrackerInjectionReport(
                                torrentID: handle.id.rawValue,
                                requestedTrackers: trackerUpdates.count,
                                resultingTrackers: nil,
                                error: error.localizedDescription
                            )
                        )
                    }
                }
            }

            var sessionSamples: [SessionSample] = []
            var torrentSamples: [TorrentSample] = []
            var didWarnDiagnosticsFallback = false
            let backend = currentBackendSnapshot()

            if backend.isPlaceholderBridge {
                warnings.append(
                    "Placeholder bridge detected (bridgeVersion=\(backend.bridgeVersion)); throughput metrics are synthetic and must not be used for BT performance validation."
                )
            }

            let startedAt = Date()
            let deadline = startedAt.addingTimeInterval(TimeInterval(options.durationSeconds))

            while true {
                let now = Date()
                let timestamp = isoFormatter.string(from: now)
                let statuses = await downloader.torrentStatuses()
                let diagnosticsSample: SessionSample
                do {
                    let diagnostics = try await downloader.sessionDiagnostics()
                    diagnosticsSample = SessionSample(
                        timestamp: timestamp,
                        downloadRateBytesPerSecond: diagnostics.aggregateDownloadRateBytesPerSecond,
                        uploadRateBytesPerSecond: diagnostics.aggregateUploadRateBytesPerSecond,
                        totalConnections: diagnostics.totalConnections,
                        totalPeers: diagnostics.totalPeers,
                        totalSeeds: diagnostics.totalSeeds,
                        isDHTEnabled: diagnostics.isDHTEnabled,
                        dhtNodeCount: diagnostics.dhtNodeCount
                    )
                } catch {
                    // Fallback for bridges that do not expose session diagnostics yet.
                    let aggregateDownloadRate = statuses.reduce(0 as Int64) { partial, status in
                        partial + status.metrics.downloadRateBytesPerSecond
                    }
                    let aggregateUploadRate = statuses.reduce(0 as Int64) { partial, status in
                        partial + status.metrics.uploadRateBytesPerSecond
                    }
                    let aggregatePeers = statuses.reduce(0) { partial, status in
                        partial + status.metrics.peerCount
                    }
                    let aggregateSeeds = statuses.reduce(0) { partial, status in
                        partial + status.metrics.seedCount
                    }

                    diagnosticsSample = SessionSample(
                        timestamp: timestamp,
                        downloadRateBytesPerSecond: aggregateDownloadRate,
                        uploadRateBytesPerSecond: aggregateUploadRate,
                        totalConnections: aggregatePeers,
                        totalPeers: aggregatePeers,
                        totalSeeds: aggregateSeeds,
                        isDHTEnabled: configuration.enableDistributedHashTable,
                        dhtNodeCount: -1
                    )

                    if !didWarnDiagnosticsFallback {
                        didWarnDiagnosticsFallback = true
                        warnings.append("Session diagnostics unavailable; falling back to torrent-status aggregation.")
                    }
                }

                sessionSamples.append(diagnosticsSample)
                for status in statuses {
                    torrentSamples.append(
                        TorrentSample(
                            timestamp: timestamp,
                            torrentID: status.id.rawValue,
                            progress: status.metrics.progress,
                            downloadRateBytesPerSecond: status.metrics.downloadRateBytesPerSecond,
                            uploadRateBytesPerSecond: status.metrics.uploadRateBytesPerSecond,
                            peers: status.metrics.peerCount,
                            seeds: status.metrics.seedCount,
                            totalDownloadBytes: status.metrics.downloadedBytes,
                            totalUploadBytes: status.metrics.uploadedBytes
                        )
                    )
                }

                if now >= deadline {
                    break
                }

                try await Task.sleep(nanoseconds: UInt64(options.intervalSeconds) * 1_000_000_000)
            }

            let endedAt = Date()
            let summary = BenchmarkSummary(
                startedAt: isoFormatter.string(from: startedAt),
                endedAt: isoFormatter.string(from: endedAt),
                samplingDurationSeconds: options.durationSeconds,
                sampleIntervalSeconds: options.intervalSeconds,
                sourceCount: options.sourceInputs.count,
                addedTorrentCount: handles.count,
                profile: options.profile,
                backend: backend,
                configuration: configurationSnapshot,
                trackerInjectionReports: trackerReports,
                averageDownloadRateBytesPerSecond: average(sessionSamples.map(\.downloadRateBytesPerSecond)),
                averageUploadRateBytesPerSecond: average(sessionSamples.map(\.uploadRateBytesPerSecond)),
                p95DownloadRateBytesPerSecond: percentile(sessionSamples.map(\.downloadRateBytesPerSecond), percentile: 0.95),
                p95UploadRateBytesPerSecond: percentile(sessionSamples.map(\.uploadRateBytesPerSecond), percentile: 0.95),
                averageConnections: average(sessionSamples.map(\.totalConnections)),
                averagePeers: average(sessionSamples.map(\.totalPeers)),
                averageSeeds: average(sessionSamples.map(\.totalSeeds)),
                averageDHTNodeCount: average(sessionSamples.map(\.dhtNodeCount)),
                sessionSampleCount: sessionSamples.count,
                torrentSampleCount: torrentSamples.count,
                warnings: warnings
            )

            try writeSessionCSV(samples: sessionSamples, outputDirectory: options.outputDirectory)
            try writeTorrentCSV(samples: torrentSamples, outputDirectory: options.outputDirectory)
            try writeSummaryJSON(summary: summary, outputDirectory: options.outputDirectory)

            let archive = BenchmarkArchive(
                summary: summary,
                sessionSamples: sessionSamples,
                torrentSamples: torrentSamples
            )
            try writeArchiveJSON(archive: archive, outputDirectory: options.outputDirectory)

            await downloader.stop()
            return options.outputDirectory
        } catch {
            await downloader.stop()
            throw error
        }
    }
}

private func currentBackendSnapshot() -> BackendSnapshot {
    let backendInfo = LibtorrentApple.backendInfo
    let packageMode = ProcessInfo.processInfo.environment["LIBTORRENT_APPLE_PACKAGE_MODE"] ?? "auto"
    let normalizedBridgeVersion = backendInfo.bridgeVersion.lowercased()
    let isPlaceholderBridge =
        normalizedBridgeVersion == "bootstrap" || normalizedBridgeVersion.contains("placeholder")

    return BackendSnapshot(
        packageMode: packageMode,
        vendor: backendInfo.vendor,
        libraryVersion: backendInfo.libraryVersion,
        bridgeVersion: backendInfo.bridgeVersion,
        packageName: backendInfo.packageName,
        isPlaceholderBridge: isPlaceholderBridge
    )
}

private func makeTorrentSource(from input: SourceInput) throws -> TorrentSource {
    switch input.kind {
    case .magnet:
        guard let url = URL(string: input.value), url.scheme?.lowercased() == "magnet" else {
            throw CLIError(message: "Invalid magnet URI: \(input.value)")
        }
        return .magnetLink(url, displayName: input.displayName)
    case .file:
        let resolved = URL(fileURLWithPath: input.value).standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw CLIError(message: "Torrent file not found: \(resolved.path)")
        }
        return .torrentFile(resolved, displayName: input.displayName)
    }
}

private func writeSessionCSV(samples: [SessionSample], outputDirectory: URL) throws {
    var lines: [String] = [
        "timestamp,download_rate_Bps,upload_rate_Bps,total_connections,total_peers,total_seeds,dht_enabled,dht_node_count",
    ]

    for sample in samples {
        lines.append(
            "\(sample.timestamp),\(sample.downloadRateBytesPerSecond),\(sample.uploadRateBytesPerSecond),\(sample.totalConnections),\(sample.totalPeers),\(sample.totalSeeds),\(sample.isDHTEnabled),\(sample.dhtNodeCount)"
        )
    }

    let outputURL = outputDirectory.appendingPathComponent("session_samples.csv")
    try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
}

private func writeTorrentCSV(samples: [TorrentSample], outputDirectory: URL) throws {
    var lines: [String] = [
        "timestamp,torrent_id,progress,download_rate_Bps,upload_rate_Bps,peers,seeds,total_download_B,total_upload_B",
    ]

    for sample in samples {
        lines.append(
            "\(sample.timestamp),\(sample.torrentID),\(sample.progress),\(sample.downloadRateBytesPerSecond),\(sample.uploadRateBytesPerSecond),\(sample.peers),\(sample.seeds),\(sample.totalDownloadBytes),\(sample.totalUploadBytes)"
        )
    }

    let outputURL = outputDirectory.appendingPathComponent("torrent_samples.csv")
    try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
}

private func writeSummaryJSON(summary: BenchmarkSummary, outputDirectory: URL) throws {
    let outputURL = outputDirectory.appendingPathComponent("summary.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(summary)
    try data.write(to: outputURL, options: .atomic)
}

private func writeArchiveJSON(archive: BenchmarkArchive, outputDirectory: URL) throws {
    let outputURL = outputDirectory.appendingPathComponent("samples.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(archive)
    try data.write(to: outputURL, options: .atomic)
}

private func resolvePath(_ rawValue: String, relativeTo baseDirectory: URL) -> URL {
    let expanded = (rawValue as NSString).expandingTildeInPath
    let pathURL = URL(fileURLWithPath: expanded, relativeTo: baseDirectory)
    return pathURL.standardizedFileURL
}

private func orderedUnique(_ values: [String]) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            continue
        }
        if seen.insert(trimmed).inserted {
            result.append(trimmed)
        }
    }
    return result
}

private func average<T: BinaryInteger>(_ values: [T]) -> Double {
    guard !values.isEmpty else {
        return 0
    }
    let sum = values.reduce(0.0) { partial, value in
        partial + Double(value)
    }
    return sum / Double(values.count)
}

private func percentile(_ values: [Int64], percentile: Double) -> Int64 {
    guard !values.isEmpty else {
        return 0
    }

    let bounded = min(max(percentile, 0), 1)
    let sorted = values.sorted()
    let rank = Int(ceil(Double(sorted.count) * bounded))
    let index = min(max(rank - 1, 0), sorted.count - 1)
    return sorted[index]
}
