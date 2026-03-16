import Foundation

enum AsyncTiming {
    static func sleep(seconds: TimeInterval) async throws {
        let clampedSeconds = max(0, seconds)
        let nanosecondsDouble = clampedSeconds * 1_000_000_000
        let nanoseconds: UInt64

        if nanosecondsDouble >= Double(UInt64.max) {
            nanoseconds = UInt64.max
        } else {
            nanoseconds = UInt64(nanosecondsDouble.rounded())
        }

        try await Task.sleep(nanoseconds: nanoseconds)
    }

    static func deadline(after seconds: TimeInterval) -> Date {
        Date().addingTimeInterval(max(0, seconds))
    }
}
