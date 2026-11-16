import Foundation

/// Gom, sắp và lọc danh sách mode của một màn hình.
public enum ModeCatalog {
    /// Các độ phân giải dùng được cho desktop, không trùng, sắp theo diện tích tăng dần,
    /// cùng kích thước thì bản thường đứng trước HiDPI.
    public static func resolutions(_ modes: [DisplayModeInfo]) -> [Resolution] {
        let unique = Set(modes.filter(\.isUsableForDesktopGUI).map(\.resolution))
        return unique.sorted { a, b in
            let areaA = a.width * a.height, areaB = b.width * b.height
            if areaA != areaB { return areaA < areaB }
            if a.width != b.width { return a.width < b.width }
            return !a.isHiDPI && b.isHiDPI
        }
    }

    /// Tần số quét có sẵn cho một độ phân giải, giảm dần, không trùng (làm tròn 0.1 Hz).
    public static func refreshRates(for r: Resolution, in modes: [DisplayModeInfo]) -> [Double] {
        let rates = modes
            .filter { $0.isUsableForDesktopGUI && $0.resolution == r }
            .map { ($0.refreshRate * 10).rounded() / 10 }
        return Array(Set(rates)).sorted(by: >)
    }

    /// Các nấc cho thanh trượt: cùng loại (HiDPI hay không) và cùng tỉ lệ với mode hiện tại.
    public static func sliderModes(_ modes: [DisplayModeInfo], current: DisplayModeInfo) -> [Resolution] {
        let cur = current.resolution
        return resolutions(modes).filter {
            $0.isHiDPI == cur.isHiDPI && sameAspect($0, cur)
        }
    }

    /// Danh sách chế độ, lớn nhất trước. Mặc định giống thanh trượt (cùng loại HiDPI/thường, cùng tỉ lệ);
    /// `showAll` hiện mọi độ phân giải, mọi tỉ lệ.
    public static func listModes(_ modes: [DisplayModeInfo], current: DisplayModeInfo, showAll: Bool) -> [Resolution] {
        showAll ? resolutions(modes).reversed() : sliderModes(modes, current: current).reversed()
    }

    /// Mode cụ thể cho một độ phân giải: ưu tiên tần số yêu cầu, không có thì lấy tần số cao nhất.
    public static func bestMode(for r: Resolution, preferredRefresh: Double?, in modes: [DisplayModeInfo]) -> DisplayModeInfo? {
        let candidates = modes.filter { $0.isUsableForDesktopGUI && $0.resolution == r }
        if let hz = preferredRefresh,
           let exact = candidates.first(where: { abs($0.refreshRate - hz) < 0.05 }) {
            return exact
        }
        return candidates.max { $0.refreshRate < $1.refreshRate }
    }

    static func sameAspect(_ a: Resolution, _ b: Resolution) -> Bool {
        abs(a.aspect - b.aspect) < 0.01
    }
}
