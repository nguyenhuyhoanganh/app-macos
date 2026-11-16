import CoreGraphics

/// Sắp xếp màn hình: tính vị trí mới khi kéo một màn trên bản đồ thu nhỏ.
/// Toạ độ toàn cục kiểu CoreGraphics (gốc trên-trái của màn chính, y hướng xuống).
public enum ArrangementPlanner {
    /// Hai màn phải chung một đoạn cạnh dài ít nhất chừng này (pt) thì macOS mới coi là nối nhau.
    public static let minOverlap: CGFloat = 64
    /// Thả gần mép trên/dưới (hoặc trái/phải) của màn bên cạnh trong khoảng này thì hít cho thẳng hàng.
    public static let alignSnap: CGFloat = 80

    /// Vị trí hợp lệ gần nhất cho màn đang kéo: chạm cạnh một màn khác, không chồng lên màn nào.
    public static func snap(_ moving: CGRect, others: [CGRect]) -> CGPoint {
        guard !others.isEmpty else { return moving.origin }
        var best: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for o in others {
            let w = moving.width, h = moving.height
            let ys = clampAlign(moving.minY, length: h, along: o.minY, o.maxY)
            let xs = clampAlign(moving.minX, length: w, along: o.minX, o.maxX)
            let candidates = [
                CGPoint(x: o.maxX, y: ys),          // bên phải
                CGPoint(x: o.minX - w, y: ys),      // bên trái
                CGPoint(x: xs, y: o.maxY),          // bên dưới
                CGPoint(x: xs, y: o.minY - h),      // bên trên
            ]
            for c in candidates {
                let r = CGRect(origin: c, size: moving.size)
                guard !others.contains(where: { overlaps($0, r) }) else { continue }
                let d = hypot(c.x - moving.minX, c.y - moving.minY)
                if d < bestDistance { bestDistance = d; best = c }
            }
        }
        return best ?? moving.origin
    }

    /// Dịch toàn bộ bố cục để màn chính nằm ở (0, 0) — yêu cầu của CoreGraphics; làm tròn về số nguyên.
    public static func normalize(_ layout: [UInt32: CGRect], main: UInt32) -> [UInt32: CGPoint] {
        let o = layout[main]?.origin ?? .zero
        return layout.mapValues { CGPoint(x: ($0.minX - o.x).rounded(), y: ($0.minY - o.y).rounded()) }
    }

    /// Vị trí dọc cạnh: giữ chỗ người dùng thả nhưng vẫn chung ít nhất `minOverlap` với cạnh kia,
    /// và hít thẳng mép đầu/mép cuối khi thả đủ gần.
    static func clampAlign(_ value: CGFloat, length: CGFloat, along start: CGFloat, _ end: CGFloat) -> CGFloat {
        let overlap = min(minOverlap, length, end - start)
        var v = min(max(value, start - length + overlap), end - overlap)
        if abs(v - start) < alignSnap { v = start }                 // thẳng mép đầu
        else if abs(v + length - end) < alignSnap { v = end - length } // thẳng mép cuối
        return v
    }

    static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        return !i.isNull && i.width > 0.5 && i.height > 0.5
    }
}
