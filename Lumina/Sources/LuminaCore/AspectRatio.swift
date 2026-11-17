import Foundation

/// Một nhóm tỉ lệ khung hình có trong danh sách mode của màn (16:9, 16:10, 21:9…).
public struct AspectGroup: Hashable, Sendable {
    /// Rộng/cao của mode lớn nhất trong nhóm.
    public let value: Double
    public let label: String

    public init(value: Double, label: String) {
        self.value = value
        self.label = label
    }

    public func contains(_ r: Resolution) -> Bool { abs(r.aspect - value) < ModeCatalog.aspectTolerance }
}

extension ModeCatalog {
    /// Hai độ phân giải coi là cùng tỉ lệ khi lệch dưới mức này (1147×716 vẫn là 16:10).
    public static let aspectTolerance = 0.01

    /// Tỉ lệ thường gặp; màn siêu rộng "21:9" thực tế là 2.33–2.4 (2560×1080, 3440×1440, 3840×1600).
    static let knownAspects: [(label: String, value: Double, tolerance: Double)] = [
        ("5:4", 5.0 / 4, 0.012), ("4:3", 4.0 / 3, 0.012), ("3:2", 3.0 / 2, 0.012),
        ("16:10", 16.0 / 10, 0.012), ("16:9", 16.0 / 9, 0.012),
        ("21:9", 2.37, 0.05), ("32:9", 32.0 / 9, 0.03), ("32:10", 32.0 / 10, 0.03),
    ]

    /// Tên tỉ lệ: tên quen thuộc nếu khớp; tỉ lệ gốc của tấm nền (vd MacBook 1.54 vì tính cả dải tai thỏ)
    /// là "Gốc"; còn lại ghi dạng "1.85:1".
    public static func aspectLabel(_ value: Double, native: Double?) -> String {
        if let known = knownAspects.first(where: { abs($0.value - value) < $0.tolerance }) { return known.label }
        if let native, abs(native - value) < aspectTolerance { return "Gốc" }
        return String(format: "%.2f:1", value)
    }

    /// Các nhóm tỉ lệ của màn (gồm cả HiDPI và thường), hẹp → rộng.
    public static func aspectGroups(_ modes: [DisplayModeInfo]) -> [AspectGroup] {
        let usable = modes.filter(\.isUsableForDesktopGUI)
        // Tấm nền gốc = mode thường (1x) lớn nhất. Không lấy theo số điểm ảnh: mode HiDPI "nhiều chỗ hơn"
        // (vd 1800×1125 trên MacBook) render ở 3600×2250, lớn hơn cả tấm nền thật.
        let oneX = usable.filter { !$0.isHiDPI }
        let native = (oneX.isEmpty ? usable : oneX).max { $0.width * $0.height < $1.width * $1.height }?.resolution.aspect
        var clusters: [[Resolution]] = []
        for r in resolutions(modes).sorted(by: { $0.aspect < $1.aspect }) {
            if let last = clusters.last?.last, abs(last.aspect - r.aspect) < aspectTolerance {
                clusters[clusters.count - 1].append(r)
            } else {
                clusters.append([r])
            }
        }
        return clusters.map { group in
            let value = group.max { $0.width * $0.height < $1.width * $1.height }!.aspect
            return AspectGroup(value: value, label: aspectLabel(value, native: native))
        }
    }

    /// Đổi sang tỉ lệ khác: lấy độ phân giải của nhóm đó có chiều cao gần nhất với hiện tại
    /// (giữ cỡ chữ gần như cũ); bằng nhau thì ưu tiên cùng loại HiDPI/thường như hiện tại.
    /// `nil` khi đã đúng tỉ lệ đó hoặc nhóm không có độ phân giải nào.
    public static func resolution(for group: AspectGroup, modes: [DisplayModeInfo], current: DisplayModeInfo) -> Resolution? {
        let cur = current.resolution
        guard !group.contains(cur) else { return nil }
        return resolutions(modes).filter(group.contains).min { a, b in
            let da = abs(a.height - cur.height), db = abs(b.height - cur.height)
            if da != db { return da < db }
            if (a.isHiDPI == cur.isHiDPI) != (b.isHiDPI == cur.isHiDPI) { return a.isHiDPI == cur.isHiDPI }
            return a.width > b.width
        }
    }
}
