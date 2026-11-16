import Foundation
import ServiceManagement

/// Mở Lumina cùng máy (tính năng 31) qua SMAppService — app tự đăng ký chính nó làm login item.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Mô tả trạng thái cho người dùng / CLI.
    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: "bật"
        case .notRegistered: "tắt"
        case .requiresApproval: "chờ duyệt trong Cài đặt hệ thống › Mục đăng nhập"
        case .notFound: "không tìm thấy app (hãy chạy từ /Applications)"
        @unknown default: "không rõ"
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
