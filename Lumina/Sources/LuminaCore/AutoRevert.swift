import Foundation

/// Đếm ngược tự hoàn tác sau khi đổi chế độ hiển thị.
public struct AutoRevert: Sendable, Equatable {
    public let start: Date
    public let duration: TimeInterval

    public init(start: Date, duration: TimeInterval = 15) {
        self.start = start
        self.duration = duration
    }

    /// Số giây còn lại, làm tròn lên, không âm.
    public func remaining(at now: Date) -> Int {
        max(0, Int((duration - now.timeIntervalSince(start)).rounded(.up)))
    }

    public func isExpired(at now: Date) -> Bool {
        now.timeIntervalSince(start) >= duration
    }

    /// Tỉ lệ còn lại 0…1, cho vòng đếm ngược.
    public func fraction(at now: Date) -> Double {
        max(0, min(1, 1 - now.timeIntervalSince(start) / duration))
    }
}
