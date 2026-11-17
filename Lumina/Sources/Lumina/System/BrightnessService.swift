import CoreGraphics
import Foundation
import LuminaCore

/// Cách điều khiển độ sáng của một màn.
enum BrightnessKind: Equatable {
    case system      // DisplayServices (màn tích hợp, Studio Display…)
    case hardware    // DDC/CI qua IOAVService
    case software    // bảng gamma, khi màn không hỗ trợ DDC
}

struct BrightnessState: Equatable {
    var kind: BrightnessKind
    var value: Double   // 0…1
}

/// Đọc/ghi độ sáng cho mọi loại màn.
@MainActor
final class BrightnessService {
    private(set) var ddc: [CGDirectDisplayID: DDCChannel] = [:]
    private var ddcMax: [CGDirectDisplayID: UInt16] = [:]
    private var softwareLevel: [CGDirectDisplayID: Double] = [:]

    func rescan(_ displays: [DisplaySnapshot]) {
        ddc = DDCDiscovery.channels(for: displays)
        ddcMax = ddcMax.filter { ddc[$0.key] != nil }
    }

    func kind(for d: DisplaySnapshot) -> BrightnessKind {
        if let can = PrivateAPI.displayServicesCanChangeBrightness, can(d.id) { return .system }
        if ddc[d.id] != nil { return .hardware }
        return .software
    }

    /// Đọc độ sáng hiện tại. Với DDC, nếu màn không trả lời thì chuyển sang làm tối phần mềm.
    func read(_ d: DisplaySnapshot) async -> BrightnessState {
        switch kind(for: d) {
        case .system:
            var v: Float = 0
            _ = PrivateAPI.displayServicesGetBrightness?(d.id, &v)
            return BrightnessState(kind: .system, value: Double(v))
        case .hardware:
            if let reply = await ddc[d.id]?.read(DDCPacket.VCP.brightness.rawValue) {
                ddcMax[d.id] = reply.maximum
                return BrightnessState(kind: .hardware, value: Double(reply.current) / Double(reply.maximum))
            }
            ddc[d.id] = nil
            return BrightnessState(kind: .software, value: softwareLevel[d.id] ?? 1)
        case .software:
            return BrightnessState(kind: .software, value: softwareLevel[d.id] ?? 1)
        }
    }

    func set(_ value: Double, for d: DisplaySnapshot, kind: BrightnessKind) {
        let v = min(max(value, 0), 1)
        switch kind {
        case .system:
            _ = PrivateAPI.displayServicesSetBrightness?(d.id, Float(v))
        case .hardware:
            let maximum = ddcMax[d.id] ?? 100
            ddc[d.id]?.write(DDCPacket.VCP.brightness.rawValue, value: UInt16((v * Double(maximum)).rounded()))
        case .software:
            softwareLevel[d.id] = v
            applyGamma(v, to: d.id)
        }
    }

    /// Làm tối bằng bảng gamma; giữ tối thiểu 10% để màn không đen hẳn.
    private func applyGamma(_ v: Double, to id: CGDirectDisplayID) {
        if v >= 0.999 {
            CGDisplayRestoreColorSyncSettings()
            for (other, level) in softwareLevel where other != id && level < 0.999 { applyGamma(level, to: other) }
            return
        }
        let scale = Float(0.1 + 0.9 * v)
        let n = 256
        let table = (0..<n).map { Float($0) / Float(n - 1) * scale }
        CGSetDisplayTransferByTable(id, UInt32(n), table, table, table)
    }

    /// Đọc/ghi một mã DDC/CI bất kỳ (vd độ lợi R/G/B 0x16/0x18/0x1A).
    func readVCP(_ code: UInt8, on d: DisplaySnapshot) async -> DDCPacket.Reply? {
        await ddc[d.id]?.read(code)
    }

    func writeVCP(_ code: UInt8, value: UInt16, on d: DisplaySnapshot) {
        ddc[d.id]?.write(code, value: value)
    }

    /// Trả màu về mặc định khi thoát app.
    func restoreSoftwareDimming() {
        if softwareLevel.values.contains(where: { $0 < 0.999 }) { CGDisplayRestoreColorSyncSettings() }
    }
}
