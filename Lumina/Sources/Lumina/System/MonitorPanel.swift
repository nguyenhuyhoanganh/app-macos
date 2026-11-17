import AppKit
import CoreGraphics

/// Các điều khiển mà System Settings › Màn hình dùng nhưng macOS không có API công khai:
/// xoay màn và bật/tắt HDR (`MPDisplay` trong MonitorPanel.framework, private, nạp động).
/// Thiếu framework/hàm thì `isAvailable` = false và các điều khiển đó tự ẩn, app không crash.
@MainActor
enum MonitorPanel {
    private static let setOrientation = NSSelectorFromString("setOrientation:")
    private static let setPreferHDR = NSSelectorFromString("setPreferHDRModes:")

    static let isAvailable: Bool = {
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY) != nil
            && NSClassFromString("MPDisplayMgr") != nil && NSClassFromString("MPDisplay") != nil
    }()

    private static func responds(_ sel: Selector) -> Bool {
        guard isAvailable, let cls = NSClassFromString("MPDisplay") else { return false }
        return class_getInstanceMethod(cls, sel) != nil
    }

    static var canRotateAtAll: Bool { responds(setOrientation) }

    /// Dùng lại một MPDisplayMgr; chỉ tạo mới khi danh sách màn đang cắm đổi (danh sách màn của nó
    /// chụp lúc khởi tạo, không tự cập nhật khi cắm/rút). Không tạo mới mỗi lần: `-[MPDisplayMgr init]`
    /// rò một NSMutableArray mỗi lần gọi (đo bằng `leaks`), mà danh sách màn nạp lại mỗi lần mở popover.
    private static var manager: NSObject?
    private static var managerDisplayIDs: [CGDirectDisplayID] = []

    private static func displays() -> [NSObject] {
        guard isAvailable, let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return [] }
        let online = MirrorService.onlineDisplays()
        if manager == nil || online != managerDisplayIDs {
            manager = cls.init()
            managerDisplayIDs = online
        }
        return manager?.value(forKey: "displays") as? [NSObject] ?? []
    }

    /// Lệnh ghi (xoay, HDR) dùng MPDisplayMgr mới như System Settings mở lại: đối tượng của manager
    /// dùng lại có thể cũ sau khi đổi chế độ màn (đo: xoay 180° sau khi đổi HiDPI không ăn). Ghi chỉ
    /// xảy ra khi người dùng bấm nên rò nhỏ của `init` không đáng kể; đọc mỗi lần mở popover vẫn dùng chung.
    private static func mpDisplay(_ id: CGDirectDisplayID) -> NSObject? {
        guard isAvailable, let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return nil }
        let fresh = cls.init()
        manager = fresh
        managerDisplayIDs = MirrorService.onlineDisplays()
        return (fresh.value(forKey: "displays") as? [NSObject])?
            .first { ($0.value(forKey: "displayID") as? NSNumber)?.uint32Value == id }
    }

    struct Info: Equatable {
        var canRotate = false
        var hasHDR = false
        var hdrOn = false
    }

    /// Đọc một lượt cho mọi màn (một MPDisplayMgr), dùng khi DisplayRegistry nạp lại.
    static func info() -> [CGDirectDisplayID: Info] {
        var result: [CGDirectDisplayID: Info] = [:]
        for d in displays() {
            guard let id = (d.value(forKey: "displayID") as? NSNumber)?.uint32Value else { continue }
            func flag(_ key: String) -> Bool {
                d.responds(to: NSSelectorFromString(key)) && ((d.value(forKey: key) as? NSNumber)?.boolValue ?? false)
            }
            result[id] = Info(canRotate: canRotateAtAll && flag("canChangeOrientation"),
                              hasHDR: responds(setPreferHDR) && flag("hasHDRModes"),
                              hdrOn: flag("preferHDRModes"))
        }
        return result
    }

    static func rotation(_ id: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(id).rounded()) % 360
    }

    /// `degrees`: 0, 90, 180 hoặc 270 (theo chiều kim đồng hồ, như System Settings).
    static func setRotation(_ id: CGDirectDisplayID, degrees: Int) throws {
        guard let display = mpDisplay(id), display.responds(to: setOrientation) else {
            throw LuminaError.rotationUnavailable
        }
        typealias Fn = @convention(c) (AnyObject, Selector, Int32) -> Void
        unsafeBitCast(display.method(for: setOrientation), to: Fn.self)(display, setOrientation, Int32(degrees))
    }

    /// Công tắc "Dải động cao (HDR)" của màn ngoài trong System Settings.
    static func setHDR(_ id: CGDirectDisplayID, on: Bool) throws {
        guard let display = mpDisplay(id), display.responds(to: setPreferHDR) else {
            throw LuminaError.hdrUnavailable
        }
        typealias Fn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(display.method(for: setPreferHDR), to: Fn.self)(display, setPreferHDR, ObjCBool(on))
    }
}
