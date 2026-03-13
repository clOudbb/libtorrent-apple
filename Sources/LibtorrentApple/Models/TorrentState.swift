public enum TorrentState: String, Sendable, Hashable, Codable {
    case idle
    case running
    case paused
    case stopped
    case removed
}
