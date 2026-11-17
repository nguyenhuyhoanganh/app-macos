import Foundation

/// Phần khoét ở mép trên màn: tai thỏ (MacBook Pro/Air hiện nay), Dynamic Island (MacBook Pro OLED),
/// hoặc không có (màn ngoài, MacBook không tai thỏ). Dùng để vẽ ô màn trên bản đồ Sắp xếp.
public enum TopCutout: Equatable, Sendable {
    case none
    /// `width`: bề rộng so với bề ngang màn (0…1).
    case notch(width: Double)
    case island(width: Double)

    /// Nhận dạng từ thông tin macOS (`NSScreen.safeAreaInsets.top`, `auxiliaryTopLeftArea/RightArea`):
    /// có vùng an toàn phía trên ⇒ có phần khoét; bề rộng = phần còn lại giữa hai vùng menu bar.
    /// Màn OLED (tên có "OLED", vd "PROLED XDR") thì là Dynamic Island thay cho tai thỏ.
    public static func detect(safeAreaTop: Double, leftArea: Double?, rightArea: Double?,
                              screenWidth: Double, name: String) -> TopCutout {
        guard safeAreaTop > 0, screenWidth > 0 else { return .none }
        var fraction = 0.12   // MacBook Pro 14″: 185 / 1512
        if let l = leftArea, let r = rightArea, l > 0, r > 0 {
            fraction = min(max((screenWidth - l - r) / screenWidth, 0.04), 0.4)
        }
        return name.localizedCaseInsensitiveContains("OLED") ? .island(width: fraction) : .notch(width: fraction)
    }
}
