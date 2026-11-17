import CoreGraphics

/// Phản chiếu (mirror) / mở rộng (extend) màn hình bằng API công khai CoreGraphics —
/// tương đương "Phản chiếu" trong Cài đặt hệ thống › Màn hình.
@MainActor
enum MirrorService {
    static func onlineDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Các màn đang phản chiếu màn khác.
    static func mirroringDisplays() -> [CGDirectDisplayID] {
        onlineDisplays().filter { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
    }

    /// `on`: mọi màn khác phản chiếu `master`. `off`: tách hết ra, mỗi màn một desktop (extend).
    static func set(_ on: Bool, master: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw LuminaError.configuration(err) }
        for id in onlineDisplays() where id != master {
            err = CGConfigureDisplayMirrorOfDisplay(config, id, on ? master : kCGNullDirectDisplay)
            guard err == .success else { CGCancelDisplayConfiguration(config); throw LuminaError.configuration(err) }
        }
        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else { throw LuminaError.configuration(err) }
    }
}
