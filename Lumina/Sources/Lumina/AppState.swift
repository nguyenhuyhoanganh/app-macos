import AppKit
import CoreGraphics
import LuminaCore
import Observation

/// Thay đổi mode đang chờ người dùng xác nhận; tự hoàn tác khi hết giờ.
struct PendingChange {
    let displayID: CGDirectDisplayID
    let summary: String
    let previousModeID: Int32
    let timer: AutoRevert
}

@MainActor @Observable
final class AppState {
    let registry = DisplayRegistry()
    @ObservationIgnored let brightnessService = BrightnessService()
    @ObservationIgnored private lazy var modeService = ModeService(registry: registry)

    private(set) var brightness: [CGDirectDisplayID: BrightnessState] = [:]
    private(set) var pending: PendingChange?
    private(set) var now = Date()
    var errorMessage: String?

    @ObservationIgnored private var ticker: Timer?

    init() {
        registry.onChange = { [weak self] in self?.displaysChanged() }
        displaysChanged()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.brightnessService.restoreSoftwareDimming() }
        }
    }

    var displays: [DisplaySnapshot] { registry.displays }

    // MARK: Nhận diện màn

    private func displaysChanged() {
        brightnessService.rescan(registry.displays)
        let ids = Set(registry.displays.map(\.id))
        brightness = brightness.filter { ids.contains($0.key) }
        if let p = pending, !ids.contains(p.displayID) { finishPending() } // màn bị rút: bỏ hoàn tác
        refreshBrightness()
    }

    // MARK: Độ sáng

    func refreshBrightness() {
        for d in registry.displays {
            Task { [weak self] in
                guard let self else { return }
                let state = await self.brightnessService.read(d)
                self.brightness[d.id] = state
            }
        }
    }

    func setBrightness(_ value: Double, for d: DisplaySnapshot) {
        guard var state = brightness[d.id] else { return }
        state.value = value
        brightness[d.id] = state
        brightnessService.set(value, for: d, kind: state.kind)
    }

    // MARK: Độ phân giải

    func select(_ resolution: Resolution, on d: DisplaySnapshot) {
        guard resolution != d.current.resolution,
              let mode = ModeCatalog.bestMode(for: resolution, preferredRefresh: d.current.refreshRate, in: d.modes) else { return }
        // Đổi tiếp khi đang chờ xác nhận: vẫn hoàn tác về mode ban đầu.
        let previous = pending?.displayID == d.id ? pending!.previousModeID : d.current.id
        if let p = pending, p.displayID != d.id { finishPending() }
        do {
            try modeService.apply(modeID: mode.id, to: d.id)
            pending = PendingChange(displayID: d.id, summary: resolution.label, previousModeID: previous,
                                    timer: AutoRevert(start: Date()))
            startTicker()
        } catch {
            errorMessage = error.localizedDescription
        }
        registry.scheduleReload()
    }

    func keepPending() { finishPending() }

    func revertPending() {
        guard let p = pending else { return }
        finishPending()
        guard registry.display(p.displayID) != nil else { return }
        do { try modeService.apply(modeID: p.previousModeID, to: p.displayID) }
        catch { errorMessage = error.localizedDescription }
        registry.scheduleReload()
    }

    private func finishPending() {
        pending = nil
        ticker?.invalidate()
        ticker = nil
    }

    /// Đếm ngược chạy trong AppState, không phụ thuộc popover có mở hay không.
    private func startTicker() {
        ticker?.invalidate()
        now = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.pending else { return }
                self.now = Date()
                if p.timer.isExpired(at: self.now) { self.revertPending() }
            }
        }
    }
}
