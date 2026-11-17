import AppKit
import CoreGraphics
import LuminaCore
import Observation

/// Thay đổi đang chờ người dùng xác nhận (độ phân giải hoặc góc xoay); tự hoàn tác khi hết giờ.
struct PendingChange {
    enum Revert: Equatable {
        case mode(Int32)
        case rotation(Int)
    }

    let displayID: CGDirectDisplayID
    let summary: String
    let revert: Revert
    let timer: AutoRevert
}

@MainActor @Observable
final class AppState {
    let registry = DisplayRegistry()
    @ObservationIgnored let brightnessService = BrightnessService()
    @ObservationIgnored private let sleepGuard = SleepGuard()
    @ObservationIgnored private lazy var modeService = ModeService(registry: registry)

    private(set) var brightness: [CGDirectDisplayID: BrightnessState] = [:]
    private(set) var pending: PendingChange?
    private(set) var now = Date()
    var errorMessage: String?

    /// Công cụ: ngăn màn hình ngủ. Nhớ qua các lần mở app.
    var preventSleep: Bool = UserDefaults.standard.bool(forKey: "preventSleep") {
        didSet {
            guard preventSleep != oldValue else { return }
            if !sleepGuard.set(preventSleep) {
                errorMessage = "Không bật được chế độ ngăn ngủ."
                preventSleep = false
            }
            UserDefaults.standard.set(preventSleep, forKey: "preventSleep")
        }
    }

    /// Mở cùng máy. Giữ ở đây (không phải trong view) để popover và cửa sổ luôn hiện cùng một giá trị.
    private(set) var launchAtLogin = LoginItem.isEnabled

    /// Gọi đăng ký/huỷ rồi giữ giá trị người dùng chọn. Không đọc lại trạng thái ngay:
    /// SMAppService cập nhật hơi trễ, đọc lại ngay sẽ thấy "chưa bật" và làm công tắc nhảy ngược (lỗi đã gặp).
    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            launchAtLogin = on
        } catch {
            errorMessage = "Không đổi được “Mở cùng máy”: \(error.localizedDescription)"
            launchAtLogin = LoginItem.isEnabled
        }
    }

    func refreshLoginItem() { launchAtLogin = LoginItem.isEnabled }

    @ObservationIgnored private var ticker: Timer?

    init() {
        if preventSleep { sleepGuard.set(true) }
        nitsProfiles = Self.loadProfiles()
        defer { updateSyncTimer() }
        registry.onChange = { [weak self] in self?.displaysChanged() }
        displaysChanged()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.brightnessService.restoreSoftwareDimming() }
        }
    }

    var displays: [DisplaySnapshot] { registry.displays }

    // MARK: Nhận diện màn

    private func displaysChanged() {
        migrateLegacyKeys()
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
                // Đồng bộ sau khi đọc xong BẤT KỲ màn nào: màn tích hợp đọc rất nhanh, DDC của màn ngoài
                // về sau. Nếu chỉ đồng bộ khi đọc xong màn chuẩn thì lúc đó chưa có độ sáng màn ngoài,
                // và màn ngoài cứ đứng nguyên mức cũ tới khi màn chuẩn đổi (lỗi đã gặp sau khi khởi động).
                if self.brightnessSync { self.syncBrightness() }
            }
        }
    }

    func setBrightness(_ value: Double, for d: DisplaySnapshot) {
        guard var state = brightness[d.id] else { return }
        state.value = value
        brightness[d.id] = state
        brightnessService.set(value, for: d, kind: state.kind)
        guard brightnessSync, let source = syncSource else { return }
        if d.id == source.id {
            syncBrightness()
        } else if let sv = brightness[source.id]?.value, BrightnessSync.isCalibrationDrag(value) {
            // Kéo màn phụ trong lúc đồng bộ = chỉnh cho khớp mắt: nhớ thành mức bù của màn đó.
            let sp = profile(for: source)
            updateProfile(d, resync: false) {
                $0.ratio = BrightnessSync.ratio(sourceValue: sv, source: sp, targetValue: value, target: $0)
            }
        }
    }

    // MARK: Đồng bộ độ sáng (theo nit)

    /// Các màn khác bám theo số nit (ước lượng) của màn chuẩn — màn tích hợp nếu có.
    var brightnessSync: Bool = UserDefaults.standard.bool(forKey: "brightnessSync") {
        didSet {
            guard brightnessSync != oldValue else { return }
            UserDefaults.standard.set(brightnessSync, forKey: "brightnessSync")
            updateSyncTimer()
            if brightnessSync { syncBrightness() }
        }
    }

    /// Hồ sơ nit người dùng đã chỉnh, theo `DisplayIdentity.key` (nhớ qua các lần cắm/rút).
    private(set) var nitsProfiles: [String: NitsProfile] = [:]
    @ObservationIgnored private var syncTimer: Timer?

    var syncSource: DisplaySnapshot? {
        registry.displays.first(where: \.isBuiltIn) ?? registry.displays.first(where: \.isMain)
    }

    var canSyncBrightness: Bool {
        registry.displays.count >= 2 && registry.displays.allSatisfy { brightness[$0.id] != nil }
    }

    func profile(for d: DisplaySnapshot) -> NitsProfile {
        if let p = nitsProfiles[d.identity.key] { return p }
        let screen = NSScreen.screens.first { $0.displayID == d.id }
        return NitsProfile.defaults(name: screen?.localizedName ?? d.name, isBuiltIn: d.isBuiltIn,
                                    hardwareControl: brightness[d.id]?.kind != .software,
                                    hdrHeadroom: Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1))
    }

    /// Màn chuẩn đang bật "Tự động điều chỉnh độ sáng": khi phòng sáng, macOS có thể đẩy màn sáng thêm
    /// (tới ~1000 nit) mà thanh độ sáng không đổi — Lumina không thấy phần đó nên màn kia có thể lệch.
    var syncSourceAutoBrightness: Bool {
        guard let source = syncSource else { return false }
        return PrivateAPI.isAutoBrightnessOn(source.id) ?? false
    }

    /// Màn này đang đứng ở giới hạn vì màn chuẩn sáng/tối hơn mức nó làm được.
    func syncLimit(for d: DisplaySnapshot) -> BrightnessSync.Limit {
        guard brightnessSync, let source = syncSource, d.id != source.id,
              let sv = brightness[source.id]?.value else { return .none }
        return BrightnessSync.limit(sourceValue: sv, source: profile(for: source), target: profile(for: d))
    }

    /// Số nit ước lượng của màn lúc này.
    func nits(for d: DisplaySnapshot) -> Double? {
        brightness[d.id].map { profile(for: d).nits(at: $0.value) }
    }

    func updateProfile(_ d: DisplaySnapshot, resync: Bool = true, _ change: (inout NitsProfile) -> Void) {
        var p = profile(for: d)
        change(&p)
        p.maxNits = max(p.maxNits, p.minNits + 10)
        nitsProfiles[d.identity.key] = p
        Self.saveProfiles(nitsProfiles)
        if resync, brightnessSync { syncBrightness() }
    }

    func resetProfile(_ d: DisplaySnapshot) {
        nitsProfiles[d.identity.key] = nil
        Self.saveProfiles(nitsProfiles)
        if brightnessSync { syncBrightness() }
    }

    /// Đặt mọi màn khác theo số nit của màn chuẩn.
    func syncBrightness() {
        guard brightnessSync, let source = syncSource, let sv = brightness[source.id]?.value else { return }
        let sp = profile(for: source)
        for d in registry.displays where d.id != source.id {
            guard var state = brightness[d.id] else { continue }
            let v = BrightnessSync.target(sourceValue: sv, source: sp, target: profile(for: d))
            guard abs(v - state.value) > 0.003 else { continue }
            state.value = v
            brightness[d.id] = state
            brightnessService.set(v, for: d, kind: state.kind)
        }
    }

    /// Bám theo cả thay đổi ngoài Lumina (phím độ sáng, tự chỉnh theo ánh sáng phòng): đọc màn
    /// tích hợp 3 lần/giây — DisplayServices đọc rất nhẹ. Màn chuẩn là DDC thì không dò (đọc DDC chậm).
    private func updateSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
        guard brightnessSync else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let source = self.syncSource, var state = self.brightness[source.id],
                      state.kind == .system, let get = PrivateAPI.displayServicesGetBrightness else { return }
                var v: Float = 0
                guard get(source.id, &v) == 0 else { return }
                guard abs(Double(v) - state.value) > 0.003 else { return }
                state.value = Double(v)
                self.brightness[source.id] = state
                self.syncBrightness()
            }
        }
        syncTimer?.tolerance = 0.05   // cho macOS gộp lần thức với timer khác (tiết kiệm pin), trễ thêm ≤ 50 ms
    }

    /// Cài đặt lưu theo khoá cũ (unit number, đổi sau mỗi lần khởi động) → chuyển sang khoá ổn định.
    /// Chỉ chuyển khi đang cắm đúng MỘT màn cùng hãng + model, để không gán nhầm giữa hai màn giống hệt.
    private func migrateLegacyKeys() {
        let defaults = UserDefaults.standard
        for d in registry.displays where d.identity.serial == 0 && d.identity.uuid != nil {
            let same = registry.displays.filter { $0.identity.vendor == d.identity.vendor && $0.identity.model == d.identity.model }
            guard same.count == 1 else { continue }
            let prefix = d.identity.legacyKeyPrefix, key = d.identity.key
            if nitsProfiles[key] == nil, let old = nitsProfiles.keys.sorted().first(where: { $0.hasPrefix(prefix) }) {
                nitsProfiles[key] = nitsProfiles[old]
            }
            nitsProfiles = nitsProfiles.filter { !$0.key.hasPrefix(prefix) }
            if defaults.data(forKey: "whiteBalance." + key) == nil,
               let old = defaults.dictionaryRepresentation().keys.first(where: { $0.hasPrefix("whiteBalance." + prefix) }) {
                defaults.set(defaults.data(forKey: old), forKey: "whiteBalance." + key)
            }
            for old in defaults.dictionaryRepresentation().keys where old.hasPrefix("whiteBalance." + prefix) {
                defaults.removeObject(forKey: old)
            }
        }
        Self.saveProfiles(nitsProfiles)
    }

    private static func loadProfiles() -> [String: NitsProfile] {
        guard let data = UserDefaults.standard.data(forKey: "nitsProfiles") else { return [:] }
        return (try? JSONDecoder().decode([String: NitsProfile].self, from: data)) ?? [:]
    }

    private static func saveProfiles(_ profiles: [String: NitsProfile]) {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "nitsProfiles") }
    }

    // MARK: Độ phân giải

    /// Báo trước khi Lumina tự đổi cấu hình màn: popover không coi việc mất focus ngay sau đó
    /// (do hệ thống dựng lại màn) là người dùng bấm ra ngoài.
    private func willReconfigure() {
        NotificationCenter.default.post(name: .luminaWillReconfigure, object: nil)
    }

    func select(_ resolution: Resolution, on d: DisplaySnapshot) {
        guard resolution != d.current.resolution,
              let mode = ModeCatalog.bestMode(for: resolution, preferredRefresh: d.current.refreshRate, in: d.modes) else { return }
        willReconfigure()
        // Đổi tiếp khi đang chờ xác nhận: vẫn hoàn tác về mode ban đầu.
        var previous = d.current.id
        if let p = pending {
            if p.displayID == d.id, case .mode(let id) = p.revert { previous = id } else { finishPending() }
        }
        do {
            try modeService.apply(modeID: mode.id, to: d.id)
            pending = PendingChange(displayID: d.id, summary: resolution.label, revert: .mode(previous),
                                    timer: AutoRevert(start: Date()))
            startTicker()
        } catch {
            errorMessage = error.localizedDescription
        }
        registry.scheduleReload()
    }

    // MARK: Xoay màn hình

    /// Xoay một màn; cũng chờ xác nhận và tự hoàn tác sau 15 giây như đổi độ phân giải
    /// (xoay nhầm thì màn hình khó dùng để bấm "Hoàn tác").
    func rotate(_ d: DisplaySnapshot, to degrees: Int) {
        guard degrees != d.rotation else { return }
        willReconfigure()
        var previous = d.rotation
        if let p = pending {
            if p.displayID == d.id, case .rotation(let r) = p.revert { previous = r } else { finishPending() }
        }
        do {
            try MonitorPanel.setRotation(d.id, degrees: degrees)
            if degrees == previous {
                finishPending()          // xoay về đúng góc ban đầu: không còn gì để hoàn tác
            } else {
                pending = PendingChange(displayID: d.id, summary: "xoay \(degrees)°", revert: .rotation(previous),
                                        timer: AutoRevert(start: Date()))
                startTicker()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        registry.scheduleReload()
    }

    /// Đưa mọi màn đang xoay về 0° (icon phát sáng của công cụ Xoay).
    func resetRotation() {
        willReconfigure()
        if let p = pending, case .rotation = p.revert { finishPending() }
        for d in registry.displays where d.rotation != 0 {
            do { try MonitorPanel.setRotation(d.id, degrees: 0) }
            catch { errorMessage = error.localizedDescription }
        }
        registry.scheduleReload()
    }

    // MARK: HDR

    /// Bật/tắt HDR (như công tắc "Dải động cao" trong Cài đặt hệ thống › Màn hình).
    func setHDR(_ d: DisplaySnapshot, on: Bool) {
        guard d.hasHDR, d.hdrOn != on else { return }
        willReconfigure()
        do { try MonitorPanel.setHDR(d.id, on: on) }
        catch { errorMessage = error.localizedDescription }
        registry.scheduleReload()
    }

    // MARK: Màu (màn ngoài)

    /// Điểm trắng (độ lợi R/G/B) đọc qua DDC, theo màn.
    private(set) var whiteBalance: [CGDirectDisplayID: WhiteBalance] = [:]
    /// Tăng mỗi khi đổi hồ sơ màu, để giao diện đọc lại tên hồ sơ.
    private(set) var colorProfileRevision = 0

    func refreshWhiteBalance(_ d: DisplaySnapshot) {
        Task { [weak self] in
            guard let self else { return }
            var values: [Int] = []
            for (_, code) in WhiteBalance.codes {
                guard let reply = await self.brightnessService.readVCP(code, on: d) else { return }
                values.append(Int(reply.current))
            }
            self.whiteBalance[d.id] = WhiteBalance(red: values[0], green: values[1], blue: values[2])
        }
    }

    /// Giá trị gốc trước lần đầu Lumina chỉnh, để "Khôi phục" (nhớ qua các lần mở app).
    func originalWhiteBalance(_ d: DisplaySnapshot) -> WhiteBalance? {
        guard let data = UserDefaults.standard.data(forKey: "whiteBalance." + d.identity.key) else { return nil }
        return try? JSONDecoder().decode(WhiteBalance.self, from: data)
    }

    func setWhiteBalance(_ wb: WhiteBalance, for d: DisplaySnapshot) {
        guard let current = whiteBalance[d.id] else { return }
        if originalWhiteBalance(d) == nil, let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: "whiteBalance." + d.identity.key)
        }
        whiteBalance[d.id] = wb
        for (path, code) in WhiteBalance.codes where wb[keyPath: path] != current[keyPath: path] {
            brightnessService.writeVCP(code, value: UInt16(min(max(wb[keyPath: path], 0), 100)), on: d)
        }
    }

    func restoreWhiteBalance(_ d: DisplaySnapshot) {
        guard let original = originalWhiteBalance(d) else { return }
        setWhiteBalance(original, for: d)
        UserDefaults.standard.removeObject(forKey: "whiteBalance." + d.identity.key)
    }

    func useDisplayP3(_ d: DisplaySnapshot) {
        do { try ColorService.useDisplayP3(d.id) }
        catch { errorMessage = error.localizedDescription }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.colorProfileRevision += 1 }
    }

    // MARK: Màn chính, phản chiếu

    func makeMain(_ d: DisplaySnapshot) {
        guard !d.isMain else { return }
        willReconfigure()
        do { try ArrangementService().makeMain(d.id, in: registry.displays) }
        catch { errorMessage = "Không đổi được màn chính: \(error.localizedDescription)" }
        registry.scheduleReload()
    }

    /// Đang phản chiếu: có màn đang mirror màn khác.
    var isMirroring: Bool { !registry.mirroring.isEmpty }
    /// Có ít nhất hai màn đang cắm (kể cả màn đang phản chiếu) thì mới bật phản chiếu được.
    var canMirror: Bool { registry.displays.count + registry.mirroring.count >= 2 }

    func setMirroring(_ on: Bool) {
        guard on != isMirroring, let main = registry.displays.first(where: \.isMain) ?? registry.displays.first else { return }
        willReconfigure()
        if pending != nil { revertPending() }     // đang chờ xác nhận đổi mode/xoay: hoàn tác trước
        do { try MirrorService.set(on, master: main.id) }
        catch { errorMessage = "Không \(on ? "bật" : "tắt") được phản chiếu: \(error.localizedDescription)" }
        registry.scheduleReload()
    }

    // MARK: Sắp xếp màn hình

    func moveDisplay(_ id: CGDirectDisplayID, to proposed: CGPoint) {
        willReconfigure()
        do { try ArrangementService().move(id, to: proposed, in: registry.displays) }
        catch { errorMessage = "Không sắp xếp được màn hình: \(error.localizedDescription)" }
        registry.scheduleReload()
    }

    func keepPending() { finishPending() }

    func revertPending() {
        guard let p = pending else { return }
        willReconfigure()
        finishPending()
        guard registry.display(p.displayID) != nil else { return }
        do {
            switch p.revert {
            case .mode(let id): try modeService.apply(modeID: id, to: p.displayID)
            case .rotation(let degrees): try MonitorPanel.setRotation(p.displayID, degrees: degrees)
            }
        } catch { errorMessage = error.localizedDescription }
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
