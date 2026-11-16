import CoreGraphics
import Foundation

/// Black bars baked into a video, as fractions of its width and height. Playback zooms
/// just enough to push them off screen.
public struct VideoCrop: Codable, Equatable, Hashable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double

    public static let none = VideoCrop(left: 0, right: 0, top: 0, bottom: 0)

    public init(left: Double, right: Double, top: Double, bottom: Double) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public var isEmpty: Bool { self == .none }

    /// Where the whole video goes so that the part inside the bars fills `bounds` without
    /// stretching. Layer coordinates start at the bottom, so a top bar moves the video up.
    public func playerFrame(videoSize: CGSize, in bounds: CGRect) -> CGRect {
        let content = CGSize(
            width: videoSize.width * (1 - left - right),
            height: videoSize.height * (1 - top - bottom)
        )
        guard content.width > 0, content.height > 0 else { return bounds }
        let scale = max(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let center = CGPoint(
            x: bounds.midX - (left - right) / 2 * size.width,
            y: bounds.midY - (bottom - top) / 2 * size.height
        )
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

public enum BlackBorders {
    /// Brightness, out of 255, below which a whole column or row counts as bar.
    static let darkLevel = 6.0
    /// A darker side than this is a dark scene rather than a bar.
    static let largestBar = 0.2

    /// Each array holds one sampled frame's mean brightness per column or row. A bar has to
    /// be dark in every frame, so a scene that only fades to black is left alone.
    public static func crop(columns: [[Double]], rows: [[Double]]) -> VideoCrop {
        guard !columns.isEmpty, !rows.isEmpty else { return .none }
        return VideoCrop(
            left: bar(columns, fromEnd: false),
            right: bar(columns, fromEnd: true),
            top: bar(rows, fromEnd: false),
            bottom: bar(rows, fromEnd: true)
        )
    }

    private static func bar(_ frames: [[Double]], fromEnd: Bool) -> Double {
        let fractions = frames.map { levels -> Double in
            guard !levels.isEmpty else { return 0 }
            let ordered = fromEnd ? Array(levels.reversed()) : levels
            let dark = ordered.prefix { $0 < darkLevel }.count
            return Double(dark) / Double(levels.count)
        }
        let fraction = fractions.min() ?? 0
        return fraction > largestBar ? 0 : fraction
    }
}
