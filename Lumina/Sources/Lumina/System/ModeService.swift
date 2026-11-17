import CoreGraphics
import Foundation

enum LuminaError: LocalizedError {
    case modeUnavailable
    case configuration(CGError)
    case rotationUnavailable
    case hdrUnavailable
    case colorProfileUnavailable

    var errorDescription: String? {
        switch self {
        case .modeUnavailable: "Chế độ này không còn khả dụng."
        case .configuration(let e): "Không đổi được chế độ (CGError \(e.rawValue))."
        case .rotationUnavailable: "Màn này không xoay được."
        case .hdrUnavailable: "Màn này không bật được HDR."
        case .colorProfileUnavailable: "Không đổi được hồ sơ màu."
        }
    }
}

/// Đổi mode hiển thị bằng API công khai CoreGraphics.
@MainActor
struct ModeService {
    let registry: DisplayRegistry

    func apply(modeID: Int32, to display: CGDirectDisplayID) throws {
        guard let mode = registry.modeObject(id: modeID, display: display) else { throw LuminaError.modeUnavailable }
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else { throw LuminaError.configuration(err) }
        err = CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw LuminaError.configuration(err)
        }
        err = CGCompleteDisplayConfiguration(config, .permanently)
        guard err == .success else { throw LuminaError.configuration(err) }
    }
}
