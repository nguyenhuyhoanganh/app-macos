import AppKit
import ColorSync

struct DisplayInfo: Identifiable, Equatable {
    let key: String
    let name: String
    let frame: CGRect
    var id: String { key }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Survives reboots and reconnects, unlike the CGDirectDisplayID.
    var displayKey: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return String(displayID)
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var displayInfo: DisplayInfo {
        DisplayInfo(key: displayKey, name: localizedName, frame: frame)
    }

    static func screen(forKey key: String) -> NSScreen? {
        screens.first { $0.displayKey == key }
    }
}
