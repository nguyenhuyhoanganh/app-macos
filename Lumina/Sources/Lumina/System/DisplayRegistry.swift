import AppKit
import CoreGraphics
import LuminaCore
import Observation

struct DisplaySnapshot: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let identity: DisplayIdentity
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let sizeMM: CGSize
    /// Vị trí trong bố cục toàn cục (pt, gốc trên-trái màn chính).
    let bounds: CGRect
    let current: DisplayModeInfo
    let modes: [DisplayModeInfo]
    /// Góc xoay hiện tại (0/90/180/270) và màn có cho xoay không.
    let rotation: Int
    let canRotate: Bool
    /// Màn hỗ trợ HDR (công tắc "Dải động cao" của System Settings) và đang bật HDR.
    let hasHDR: Bool
    let hdrOn: Bool

    var diagonal: Double? {
        sizeMM.width > 0 ? diagonalInches(widthMM: sizeMM.width, heightMM: sizeMM.height) : nil
    }
}

/// Danh sách màn hình đang cắm; tự cập nhật khi cắm/rút hoặc đổi mode (không polling).
@MainActor @Observable
final class DisplayRegistry {
    private(set) var displays: [DisplaySnapshot] = []
    /// Màn đang phản chiếu màn khác (không có trong `displays`).
    private(set) var mirroring: [CGDirectDisplayID] = []
    @ObservationIgnored private var modeObjects: [CGDirectDisplayID: [Int32: CGDisplayMode]] = [:]
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        reload()
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .luminaDisplaysChanged, object: nil)
            }
        }, nil)
        NotificationCenter.default.addObserver(forName: .luminaDisplaysChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    /// Gộp nhiều callback liên tiếp thành một lần reload sau 300 ms.
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return }

        var snapshots: [DisplaySnapshot] = []
        let panel = MonitorPanel.info()
        var objects: [CGDirectDisplayID: [Int32: CGDisplayMode]] = [:]
        for id in ids.prefix(Int(count)) {
            // Màn đang mirror vào màn khác không điều khiển riêng được ở đây.
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay,
                  let currentMode = CGDisplayCopyDisplayMode(id) else { continue }
            let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let all = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
            objects[id] = Dictionary(all.map { ($0.ioDisplayModeID, $0) }, uniquingKeysWith: { a, _ in a })

            let builtIn = CGDisplayIsBuiltin(id) != 0
            snapshots.append(DisplaySnapshot(
                id: id,
                identity: DisplayIdentity(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                          serial: CGDisplaySerialNumber(id), unitNumber: CGDisplayUnitNumber(id)),
                name: Self.name(for: id, builtIn: builtIn),
                isBuiltIn: builtIn,
                isMain: CGDisplayIsMain(id) != 0,
                sizeMM: CGDisplayScreenSize(id),
                bounds: CGDisplayBounds(id),
                current: Self.info(currentMode),
                modes: all.map(Self.info),
                rotation: MonitorPanel.rotation(id),
                canRotate: panel[id]?.canRotate ?? false,
                hasHDR: panel[id]?.hasHDR ?? false,
                hdrOn: panel[id]?.hdrOn ?? false
            ))
        }
        snapshots.sort { a, b in a.isBuiltIn != b.isBuiltIn ? a.isBuiltIn : a.id < b.id }

        modeObjects = objects
        let mirrored = ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
        if mirrored != mirroring { mirroring = Array(mirrored) }
        if snapshots != displays {
            displays = snapshots
            onChange?()
        }
    }

    func modeObject(id: Int32, display: CGDirectDisplayID) -> CGDisplayMode? {
        modeObjects[display]?[id]
    }

    func display(_ id: CGDirectDisplayID) -> DisplaySnapshot? {
        displays.first { $0.id == id }
    }

    private static func info(_ m: CGDisplayMode) -> DisplayModeInfo {
        DisplayModeInfo(id: m.ioDisplayModeID, width: m.width, height: m.height,
                        pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
                        refreshRate: m.refreshRate, isUsableForDesktopGUI: m.isUsableForDesktopGUI())
    }

    private static func name(for id: CGDirectDisplayID, builtIn: Bool) -> String {
        if builtIn { return "Màn hình tích hợp" }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Màn hình \(id)"
    }
}

extension Notification.Name {
    static let luminaDisplaysChanged = Notification.Name("LuminaDisplaysChanged")
    static let luminaWillReconfigure = Notification.Name("LuminaWillReconfigure")
}
