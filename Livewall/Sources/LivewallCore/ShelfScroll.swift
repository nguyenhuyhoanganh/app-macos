import Foundation

/// The wallpaper shelf scrolls sideways. A mouse wheel only turns vertically, and macOS
/// leaves that to Shift, so the shelf turns it sideways itself and adds page buttons.
public struct ShelfScroll: Equatable, Sendable {
    public static let pointsPerLine = 40.0
    static let pageFraction = 0.8
    /// Layout rounding leaves the offset a hair off an end.
    static let tolerance = 2.0

    public var contentWidth: Double
    public var visibleWidth: Double

    public init(contentWidth: Double, visibleWidth: Double) {
        self.contentWidth = contentWidth
        self.visibleWidth = visibleWidth
    }

    public var maxOffset: Double { max(0, contentWidth - visibleWidth) }

    public func edges(at offset: Double) -> (hasEarlier: Bool, hasLater: Bool) {
        (offset > Self.tolerance, offset < maxOffset - Self.tolerance)
    }

    public func page(from offset: Double, forward: Bool) -> Double {
        clamp(offset + (forward ? 1 : -1) * visibleWidth * Self.pageFraction)
    }

    /// The new offset for a mostly vertical wheel or swipe, or nil to leave the event alone.
    /// Wheel notches arrive in lines; trackpads and smooth-scrolling mice in points.
    public func wheel(from offset: Double, deltaX: Double, deltaY: Double, isPrecise: Bool) -> Double? {
        guard maxOffset > 0, abs(deltaY) > abs(deltaX) else { return nil }
        let points = isPrecise ? deltaY : deltaY * Self.pointsPerLine
        return clamp(offset - points)
    }

    private func clamp(_ offset: Double) -> Double {
        min(max(offset, 0), maxOffset)
    }
}
