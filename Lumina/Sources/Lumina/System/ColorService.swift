import AppKit
import ColorSync
import CoreGraphics

/// Hồ sơ màu (ICC) của màn — như "Hồ sơ màu" trong Cài đặt hệ thống › Màn hình.
@MainActor
enum ColorService {
    static let displayP3URL = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles/Display P3.icc")

    /// Tên hồ sơ màu đang dùng, vd "Display P3", "Color LCD".
    static func profileName(_ id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { $0.displayID == id }?.colorSpace?.localizedName
    }

    static func usesDisplayP3(_ id: CGDirectDisplayID) -> Bool {
        profileName(id) == "Display P3"
    }

    /// Gán Display P3 (gam màu của màn Mac) cho màn này, cho người dùng hiện tại.
    static func useDisplayP3(_ id: CGDirectDisplayID) throws {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              FileManager.default.fileExists(atPath: displayP3URL.path) else { throw LuminaError.colorProfileUnavailable }
        let profiles: [CFString: Any] = [
            kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): displayP3URL as CFURL,
            kColorSyncProfileUserScope.takeUnretainedValue(): kCFPreferencesCurrentUser,
        ]
        guard ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid,
                                               profiles as CFDictionary) else { throw LuminaError.colorProfileUnavailable }
    }
}

/// Điểm trắng của màn ngoài qua DDC: độ lợi đỏ/lục/lam (VCP 0x16/0x18/0x1A, 0…100).
struct WhiteBalance: Codable, Equatable {
    var red: Int
    var green: Int
    var blue: Int

    static let codes: [(KeyPath<WhiteBalance, Int>, UInt8)] = [(\.red, 0x16), (\.green, 0x18), (\.blue, 0x1A)]
}
