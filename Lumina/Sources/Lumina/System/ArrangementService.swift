import CoreGraphics
import LuminaCore

/// Đặt vị trí các màn trong bố cục (tương đương kéo màn trong Cài đặt hệ thống › Màn hình).
@MainActor
struct ArrangementService {
    /// Đặt màn `display` vào `proposed` (toạ độ toàn cục, có thể chồng/hở), sau khi hít vào cạnh
    /// màn khác và dịch cả bố cục để màn chính ở (0,0). Trả về vị trí đã áp dụng.
    @discardableResult
    func move(_ display: CGDirectDisplayID, to proposed: CGPoint, in displays: [DisplaySnapshot]) throws -> [UInt32: CGPoint] {
        guard let moving = displays.first(where: { $0.id == display }),
              let main = displays.first(where: { $0.isMain }) else { throw LuminaError.modeUnavailable }
        let others = displays.filter { $0.id != display }.map(\.bounds)
        let snapped = ArrangementPlanner.snap(CGRect(origin: proposed, size: moving.bounds.size), others: others)

        var layout = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.bounds) })
        layout[display] = CGRect(origin: snapped, size: moving.bounds.size)
        let origins = ArrangementPlanner.normalize(layout, main: main.id)

        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw LuminaError.configuration(err) }
        for (id, p) in origins {
            err = CGConfigureDisplayOrigin(config, id, Int32(p.x), Int32(p.y))
            guard err == .success else { CGCancelDisplayConfiguration(config); throw LuminaError.configuration(err) }
        }
        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else { throw LuminaError.configuration(err) }
        return origins
    }

    /// Đặt `display` làm màn chính (có menu bar và Dock): dịch cả bố cục để nó nằm ở (0,0),
    /// vị trí tương đối giữa các màn giữ nguyên.
    func makeMain(_ display: CGDirectDisplayID, in displays: [DisplaySnapshot]) throws {
        let layout = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.bounds) })
        guard layout[display] != nil else { throw LuminaError.modeUnavailable }
        let origins = ArrangementPlanner.normalize(layout, main: display)
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw LuminaError.configuration(err) }
        for (id, p) in origins {
            err = CGConfigureDisplayOrigin(config, id, Int32(p.x), Int32(p.y))
            guard err == .success else { CGCancelDisplayConfiguration(config); throw LuminaError.configuration(err) }
        }
        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else { throw LuminaError.configuration(err) }
    }
}
