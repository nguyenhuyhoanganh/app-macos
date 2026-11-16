import CoreGraphics

public enum Coverage {
    /// True when every point of a sample grid over `area` falls inside some window.
    public static func isCovered(
        _ area: CGRect,
        by windows: [CGRect],
        columns: Int = 16,
        rows: Int = 10
    ) -> Bool {
        guard !area.isEmpty, !windows.isEmpty else { return false }
        for column in 0..<columns {
            for row in 0..<rows {
                let point = CGPoint(
                    x: area.minX + area.width * (CGFloat(column) + 0.5) / CGFloat(columns),
                    y: area.minY + area.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                )
                if !windows.contains(where: { $0.contains(point) }) { return false }
            }
        }
        return true
    }
}
