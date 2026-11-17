import CoreGraphics

/// Tính vị trí popover dưới icon menu bar (toạ độ AppKit, gốc dưới-trái).
/// Luôn tính lại từ vị trí icon hiện tại, vì đổi độ phân giải làm dịch toạ độ toàn cục của mọi màn.
public enum PopoverPlacement {
    public static let gap: CGFloat = 6       // khoảng cách dưới icon
    public static let margin: CGFloat = 8    // cách mép màn

    /// Chiều cao tối đa: từ ngay dưới icon tới đáy vùng dùng được của màn.
    public static func maxHeight(anchor: CGRect, visibleFrame: CGRect) -> CGFloat {
        max(120, anchor.minY - gap - (visibleFrame.minY + margin))
    }

    public static func frame(anchor: CGRect, visibleFrame: CGRect, size: CGSize) -> CGRect {
        let height = min(size.height, maxHeight(anchor: anchor, visibleFrame: visibleFrame))
        let top = anchor.minY - gap
        var x = anchor.midX - size.width / 2
        x = min(x, visibleFrame.maxX - margin - size.width)
        x = max(x, visibleFrame.minX + margin)
        return CGRect(x: x, y: top - height, width: size.width, height: height)
    }

    /// Vị trí icon trên menu bar của một màn khác. macOS chỉ có MỘT cửa sổ icon thật (trên menu bar
    /// đang hoạt động); menu bar các màn khác vẽ lại icon, còn cửa sổ "bản sao" của chúng báo toạ độ rác
    /// (vd sát mép phải) sau khi đổi màn chính. Icon xếp từ mép phải như nhau trên mọi màn, nên giữ đúng
    /// khoảng cách tới mép phải của icon thật (đo lúc chạy), và cùng độ lệch so với đáy menu bar.
    public static func mirroredAnchor(_ icon: CGRect, from source: CGRect, sourceVisibleFrame: CGRect,
                                      to target: CGRect, targetVisibleFrame: CGRect) -> CGRect {
        let fromRight = source.maxX - icon.minX
        let y: CGFloat
        if source.maxY - sourceVisibleFrame.maxY > 1, target.maxY - targetVisibleFrame.maxY > 1 {
            // Menu bar hiện ở cả hai màn (cao có thể khác nhau, vd màn có tai thỏ): bám đáy menu bar.
            y = targetVisibleFrame.maxY + (icon.minY - sourceVisibleFrame.maxY)
        } else {
            // Menu bar tự ẩn: bám mép trên màn.
            y = target.maxY - (source.maxY - icon.minY)
        }
        return CGRect(x: target.maxX - fromRight, y: y, width: icon.width, height: icon.height)
    }

    /// Icon chỉ dùng làm mốc khi nó nằm trọn trong một màn (lúc đổi mode nó có thể tạm ở toạ độ rác).
    public static func isUsableAnchor(_ anchor: CGRect, screenFrame: CGRect?) -> Bool {
        guard let screenFrame, anchor.width > 0, anchor.height > 0 else { return false }
        return screenFrame.contains(CGPoint(x: anchor.midX, y: anchor.midY))
    }
}
