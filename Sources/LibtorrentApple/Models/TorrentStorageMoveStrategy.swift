import Foundation

public enum TorrentStorageMoveStrategy: Int32, Sendable, Hashable, Codable, CaseIterable {
    case replaceExisting = 0
    case failIfExists = 1
    case keepExisting = 2
    case resetSavePath = 3
    case resetSavePathUnchecked = 4
}
