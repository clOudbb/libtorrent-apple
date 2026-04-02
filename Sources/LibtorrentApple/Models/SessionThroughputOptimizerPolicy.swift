import Foundation

public struct SessionThroughputOptimizerPolicy: Sendable, Hashable, Codable {
    public var sampleIntervalSeconds: TimeInterval
    public var lowSpeedThresholdBytesPerSecond: Int64
    public var recoverySpeedThresholdBytesPerSecond: Int64
    public var consecutiveLowSpeedWindowsForBoost: Int
    public var consecutiveZeroSpeedWindowsForReannounce: Int
    public var stableRecoveryWindowsForRestore: Int
    public var cooldownSeconds: TimeInterval
    public var boostedConnectionSpeed: Int
    public var boostedTorrentConnectBoost: Int
    public var boostedMaxOutgoingRequestQueueSize: Int
    public var boostedMaxAllowedIncomingRequestQueueSize: Int
    public var boostedPeerTurnover: Int?
    public var boostedPeerTurnoverCutoff: Int?
    public var boostedPeerTurnoverInterval: Int?

    public init(
        sampleIntervalSeconds: TimeInterval = 2,
        lowSpeedThresholdBytesPerSecond: Int64 = 1_500_000,
        recoverySpeedThresholdBytesPerSecond: Int64 = 4_000_000,
        consecutiveLowSpeedWindowsForBoost: Int = 4,
        consecutiveZeroSpeedWindowsForReannounce: Int = 3,
        stableRecoveryWindowsForRestore: Int = 6,
        cooldownSeconds: TimeInterval = 10,
        boostedConnectionSpeed: Int = 80,
        boostedTorrentConnectBoost: Int = 120,
        boostedMaxOutgoingRequestQueueSize: Int = 1200,
        boostedMaxAllowedIncomingRequestQueueSize: Int = 600,
        boostedPeerTurnover: Int? = 6,
        boostedPeerTurnoverCutoff: Int? = 85,
        boostedPeerTurnoverInterval: Int? = 120
    ) {
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.lowSpeedThresholdBytesPerSecond = lowSpeedThresholdBytesPerSecond
        self.recoverySpeedThresholdBytesPerSecond = recoverySpeedThresholdBytesPerSecond
        self.consecutiveLowSpeedWindowsForBoost = consecutiveLowSpeedWindowsForBoost
        self.consecutiveZeroSpeedWindowsForReannounce = consecutiveZeroSpeedWindowsForReannounce
        self.stableRecoveryWindowsForRestore = stableRecoveryWindowsForRestore
        self.cooldownSeconds = cooldownSeconds
        self.boostedConnectionSpeed = boostedConnectionSpeed
        self.boostedTorrentConnectBoost = boostedTorrentConnectBoost
        self.boostedMaxOutgoingRequestQueueSize = boostedMaxOutgoingRequestQueueSize
        self.boostedMaxAllowedIncomingRequestQueueSize = boostedMaxAllowedIncomingRequestQueueSize
        self.boostedPeerTurnover = boostedPeerTurnover
        self.boostedPeerTurnoverCutoff = boostedPeerTurnoverCutoff
        self.boostedPeerTurnoverInterval = boostedPeerTurnoverInterval
    }

    public static let `default` = SessionThroughputOptimizerPolicy()
}
