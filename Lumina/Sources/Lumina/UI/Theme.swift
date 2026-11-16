import SwiftUI

/// Màu và kích thước cho giao diện Liquid Glass.
/// Chữ và nền dùng màu ngữ nghĩa của hệ thống để tự theo sáng/tối và mức kính người dùng chọn;
/// trạng thái chọn dùng màu nhấn của máy.
enum Theme {
    /// Xanh của icon app (#4DA3FF) — dùng cho công tắc đang bật.
    static let accentBlue = Color(red: 0.30, green: 0.64, blue: 1.0)

    /// Khối nền trong tấm kính (không phải kính — kính không chồng kính).
    static let platter = Color.primary.opacity(0.06)
    static let platterStroke = Color.primary.opacity(0.08)
    static let chip = Color.primary.opacity(0.09)
    static let hairline = Color.primary.opacity(0.10)

    static let popoverWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 22
    static let platterRadius: CGFloat = 14
}
