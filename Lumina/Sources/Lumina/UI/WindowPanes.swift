import AppKit
import LuminaCore
import SwiftUI

// Các trang của cửa sổ Lumina. Dùng thành phần gốc của macOS (Form .grouped, Toggle, Slider, Picker)
// để giống hệt Cài đặt hệ thống trên macOS 26/27 — Liquid Glass, sáng/tối, tương phản cao, cỡ chữ đều do
// hệ thống lo. Chỉ phần đầu trang (tên + số liệu) là bố cục riêng. Thiết kế: Claude Design › Window.dc.html.

// MARK: - Trang một màn

struct DisplayPaneV2: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot

    private static let angles = [0, 90, 180, 270]

    var body: some View {
        Form {
            Section {
                StatsRow(display: display)
            } header: {
                DisplayHeader(display: display)
            }
            brightnessSection
            resolutionSection
            layoutSection
            if !display.isBuiltIn { colorSection }
            nitsSection
        }
        .formStyle(.grouped)
        .onAppear { if !display.isBuiltIn { app.refreshWhiteBalance(display) } }
    }

    // MARK: Độ sáng

    @ViewBuilder private var brightnessSection: some View {
        if let state = app.brightness[display.id] {
            let isSource = display.id == app.syncSource?.id
            Section("Độ sáng") {
                Slider(value: Binding(get: { state.value }, set: { app.setBrightness($0, for: display) }), in: 0...1) {
                    Text("Độ sáng")
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "sun.max.fill")
                }
                .accessibilityLabel("Độ sáng \(display.name) (cửa sổ)")
                LabeledContent("Điều khiển") {
                    Text("\(kindLabel(state.kind))\(app.nits(for: display).map { " · ≈ \(Int($0.rounded())) nit" } ?? "")")
                }
                if app.canSyncBrightness {
                    Toggle(isOn: Binding(get: { app.brightnessSync }, set: { app.brightnessSync = $0 })) {
                        Text(isSource ? "Đồng bộ độ sáng giữa các màn"
                                      : "Đồng bộ theo \(app.syncSource.map(ToolsSection.shortName) ?? "màn chuẩn")")
                        Text(isSource ? "Các màn khác sáng bằng số nit của màn này."
                                      : "Sáng bằng số nit của màn chuẩn. Kéo độ sáng ở đây để bù cho khớp mắt.")
                    }
                    .accessibilityLabel("Đồng bộ độ sáng (cửa sổ \(display.name))")
                }
            }
        }
    }

    private func kindLabel(_ k: BrightnessKind) -> String {
        switch k {
        case .system: "Hệ thống"
        case .hardware: "Phần cứng (DDC)"
        case .software: "Phần mềm"
        }
    }

    // MARK: Độ phân giải

    private var resolutionSection: some View {
        let modes = ModeCatalog.sliderModes(display.modes, current: display.current)
        let groups = ModeCatalog.aspectGroups(display.modes)
        let hidpiTarget = ModeCatalog.hidpiCounterpart(display.modes, current: display.current,
                                                       hidpi: !display.current.resolution.isHiDPI)
        let all = ModeCatalog.listModes(display.modes, current: display.current, showAll: true)
        return Section("Độ phân giải") {
            if modes.count > 1 {
                ResolutionSlider(display: display, modes: modes)
            }
            Picker("Chế độ", selection: Binding(get: { display.current.resolution },
                                                 set: { app.select($0, on: display) })) {
                ForEach(all, id: \.self) { r in
                    Text(r.label + (r.isHiDPI ? " · HiDPI" : "") + " · " + ModeCatalog.aspectLabel(r.aspect, native: nil)).tag(r)
                }
            }
            .accessibilityLabel("Chế độ \(display.name) (cửa sổ)")
            Toggle(isOn: Binding(get: { display.current.resolution.isHiDPI },
                                 set: { _ in if let hidpiTarget { app.select(hidpiTarget, on: display) } })) {
                Text("HiDPI")
                Text("Vẽ mỗi điểm bằng 2×2 điểm ảnh — chữ nét như Retina.")
            }
            .disabled(hidpiTarget == nil)
            .accessibilityLabel("HiDPI \(display.name) (cửa sổ)")
            if groups.count > 1 {
                Picker("Tỉ lệ khung hình", selection: Binding(
                    get: { groups.firstIndex { $0.contains(display.current.resolution) } ?? -1 },
                    set: { i in
                        if groups.indices.contains(i),
                           let r = ModeCatalog.resolution(for: groups[i], modes: display.modes, current: display.current) {
                            app.select(r, on: display)
                        }
                    })) {
                    ForEach(groups.indices, id: \.self) { Text(groups[$0].label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Tỉ lệ \(display.name) (cửa sổ)")
            }
            LabeledContent("Tần số quét") {
                Text(ModeCatalog.refreshRates(for: display.current.resolution, in: display.modes)
                    .map { "\(Int($0.rounded())) Hz" }.joined(separator: " · "))
            }
        }
    }

    // MARK: Bố cục

    private var layoutSection: some View {
        Section("Bố cục") {
            if app.displays.count > 1 {
                LabeledContent {
                    if display.isMain {
                        Text("Đang là màn chính")
                    } else {
                        Button("Đặt làm màn chính") { app.makeMain(display) }
                            .accessibilityLabel("Đặt \(display.name) làm màn chính")
                    }
                } label: {
                    Text("Màn chính")
                    Text("Màn có menu bar và Dock.")
                }
            }
            if display.canRotate, MonitorPanel.canRotateAtAll {
                Picker("Xoay", selection: Binding(get: { display.rotation }, set: { app.rotate(display, to: $0) })) {
                    ForEach(Self.angles, id: \.self) { Text($0 == 0 ? "Chuẩn" : "\($0)°").tag($0) }
                }
                .accessibilityLabel("Xoay \(display.name) (cửa sổ)")
            }
            if app.canMirror {
                Toggle(isOn: Binding(get: { app.isMirroring }, set: { app.setMirroring($0) })) {
                    Text("Phản chiếu màn chính lên mọi màn")
                    Text("Tắt: mỗi màn một desktop (mở rộng).")
                }
                .accessibilityLabel("Phản chiếu (cửa sổ)")
            }
        }
    }

    // MARK: HDR & màu (màn ngoài)

    private var colorSection: some View {
        let _ = app.colorProfileRevision
        let profile = ColorService.profileName(display.id) ?? "—"
        return Section("HDR và màu") {
            if display.hasHDR {
                Toggle("Dải động cao (HDR)", isOn: Binding(get: { display.hdrOn }, set: { app.setHDR(display, on: $0) }))
                    .accessibilityLabel("HDR \(display.name)")
            }
            LabeledContent("Hồ sơ màu") {
                if ColorService.usesDisplayP3(display.id) {
                    Text("\(profile) · cùng gam màu với Mac")
                } else {
                    HStack {
                        Text(profile)
                        Button("Dùng Display P3") { app.useDisplayP3(display) }
                    }
                }
            }
            if let wb = app.whiteBalance[display.id] {
                LabeledContent {
                    Button("Khôi phục") { app.restoreWhiteBalance(display) }
                        .disabled(app.originalWhiteBalance(display) == nil)
                } label: {
                    Text("Điểm trắng")
                    Text("Đỏ / Lục / Lam qua DDC — có tác dụng khi màn ở chế độ màu Người dùng.")
                }
                gainSlider("Đỏ", value: wb.red) { var w = wb; w.red = $0; app.setWhiteBalance(w, for: display) }
                gainSlider("Lục", value: wb.green) { var w = wb; w.green = $0; app.setWhiteBalance(w, for: display) }
                gainSlider("Lam", value: wb.blue) { var w = wb; w.blue = $0; app.setWhiteBalance(w, for: display) }
            }
        }
    }

    private func gainSlider(_ title: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                // Không đặt step: 100 vạch chia sẽ dày đặc; làm tròn khi đặt giá trị.
                Slider(value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }), in: 0...100)
                    .labelsHidden()
                    .accessibilityLabel("\(title) \(display.name)")
                Text("\(value)").monospacedDigit().frame(width: 28, alignment: .trailing)
            }
            .frame(maxWidth: 260)
        }
    }

    // MARK: Độ sáng thật (ước lượng)

    private var nitsSection: some View {
        let p = app.profile(for: display)
        let isSource = display.id == app.syncSource?.id
        return Section {
            nitsStepper("Tối đa", value: p.maxNits, range: 100...2000, step: 50) { v in app.updateProfile(display) { $0.maxNits = v } }
            nitsStepper("Tối thiểu", value: p.minNits, range: 0...200, step: 5) { v in app.updateProfile(display) { $0.minNits = v } }
            if app.canSyncBrightness && !isSource {
                LabeledContent {
                    HStack {
                        Text(abs(p.ratio - 1) < 0.005 ? "bằng nhau" : String(format: "%+.0f%%", (p.ratio - 1) * 100)).monospacedDigit()
                        Button("Đặt lại") { app.updateProfile(display) { $0.ratio = 1 } }
                            .disabled(abs(p.ratio - 1) < 0.005)
                    }
                } label: {
                    Text("Bù so với \(app.syncSource.map(ToolsSection.shortName) ?? "màn chuẩn")")
                    Text("Tự lưu khi kéo độ sáng màn này lúc đang đồng bộ.")
                }
            }
            if isSource && app.brightnessSync && app.syncSourceAutoBrightness {
                Label("“Tự động điều chỉnh độ sáng” đang bật: khi phòng sáng, macOS có thể đẩy màn này sáng thêm (tới ~1000 nit) mà thanh độ sáng không đổi — màn khác có thể tối hơn. Tắt trong Cài đặt hệ thống › Màn hình để đồng bộ chính xác.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Độ sáng thật")
        } footer: {
            HStack {
                Text("Số nit là ước lượng theo thông số hãng.").foregroundStyle(.secondary)
                Spacer()
                Button("Về mặc định") { app.resetProfile(display) }
                    .disabled(app.nitsProfiles[display.identity.key] == nil)
            }
        }
    }

    private func nitsStepper(_ title: String, value: Double, range: ClosedRange<Double>, step: Double,
                             set: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            Stepper(value: Binding(get: { value }, set: set), in: range, step: step) {
                Text("\(Int(value)) nit").monospacedDigit()
            }
            .accessibilityLabel("\(title) \(display.name)")
        }
    }
}

/// Đầu trang: tên lớn + dòng thông số + nhãn — không vẽ hình minh hoạ.
private struct DisplayHeader: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(display.name).font(.largeTitle.weight(.bold)).foregroundStyle(.primary)
                Text(spec).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { b in
                    Text(b).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .textCase(nil)
        .padding(.bottom, 8)
    }

    private var spec: String {
        var parts = [display.isBuiltIn ? "Màn tích hợp" : "Màn ngoài"]
        if let d = display.diagonal {
            parts.append(String(format: "%.1f″", d).replacingOccurrences(of: ".0″", with: "″").replacingOccurrences(of: ".", with: ","))
        }
        parts.append("\(display.current.pixelWidth) × \(display.current.pixelHeight) điểm ảnh")
        return parts.joined(separator: " · ")
    }

    private var badges: [String] {
        var b: [String] = []
        if display.isMain { b.append("Màn chính") }
        if display.hdrOn { b.append("HDR") }
        if app.brightness[display.id]?.kind == .hardware { b.append("DDC") }
        if display.rotation != 0 { b.append("\(display.rotation)°") }
        return b
    }
}

/// Bốn số liệu chính trong một dòng của Form: độ phân giải, tần số quét, độ sáng, tỉ lệ.
private struct StatsRow: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot

    var body: some View {
        let r = display.current.resolution
        let brightness = app.brightness[display.id]
        HStack(spacing: 0) {
            stat("Độ phân giải", r.label, r.isHiDPI ? "HiDPI" : "Thường")
            Divider().frame(height: 36)
            stat("Tần số quét", "\(Int(display.current.refreshRate.rounded())) Hz", display.isBuiltIn ? "ProMotion" : " ")
            Divider().frame(height: 36)
            stat("Độ sáng", brightness.map { "\(Int(($0.value * 100).rounded()))%" } ?? "—",
                 app.nits(for: display).map { "≈ \(Int($0.rounded())) nit" } ?? " ")
            Divider().frame(height: 36)
            stat("Tỉ lệ", ModeCatalog.aspectLabel(r.aspect, native: nativeAspect), "\(display.current.pixelWidth) × \(display.current.pixelHeight)")
        }
        .padding(.vertical, 4)
    }

    private var nativeAspect: Double? {
        display.modes.filter { !$0.isHiDPI && $0.isUsableForDesktopGUI }.max { $0.width * $0.height < $1.width * $1.height }?.resolution.aspect
    }

    private func stat(_ key: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Thanh trượt độ phân giải (cùng loại HiDPI/thường, cùng tỉ lệ) có vạch chia, hai đầu "Chữ to hơn"
/// / "Nhiều chỗ hơn" — giống Cài đặt hệ thống › Màn hình. Thả tay mới đổi mode (đổi mode chậm, có tự hoàn tác).
private struct ResolutionSlider: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot
    let modes: [Resolution]

    @ViewState private var step: Double = 0
    @ViewState private var editing = false

    var body: some View {
        let shown = modes[min(max(Int(step.rounded()), 0), modes.count - 1)]
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Kích thước") {
                Text(shown.label).monospacedDigit().fontWeight(.semibold)
            }
            HStack(spacing: 10) {
                Text("Chữ to hơn").font(.caption).foregroundStyle(.secondary)
                Slider(value: $step, in: 0...Double(modes.count - 1), step: 1) { e in
                    editing = e
                    if !e { app.select(modes[min(max(Int(step.rounded()), 0), modes.count - 1)], on: display) }
                }
                .labelsHidden()
                .accessibilityLabel("Kích thước \(display.name) (cửa sổ)")
                Text("Nhiều chỗ hơn").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: display.current) { sync() }
    }

    private func sync() {
        if !editing, let i = modes.firstIndex(of: display.current.resolution) { step = Double(i) }
    }
}

// MARK: - Trang Công cụ

struct ToolsPaneV2: View {
    @Environment(AppState.self) private var app
    private static let angles = [0, 90, 180, 270]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { app.preventSleep }, set: { app.preventSleep = $0 })) {
                    Text("Ngăn ngủ")
                    Text("Giữ màn hình và máy không tự ngủ khi để yên.")
                }
                .accessibilityLabel("Ngăn ngủ")
                if app.canSyncBrightness {
                    Toggle(isOn: Binding(get: { app.brightnessSync }, set: { app.brightnessSync = $0 })) {
                        Text("Đồng bộ độ sáng")
                        Text("Các màn khác sáng bằng số nit của \(app.syncSource.map(ToolsSection.shortName) ?? "màn chuẩn").")
                    }
                    .accessibilityLabel("Đồng bộ độ sáng")
                }
            } header: {
                PaneHeader(title: "Công cụ", subtitle: "Dùng chung với popover trên menu bar")
            }
            Section("Sắp xếp màn hình") {
                DisplayMapView().frame(height: ToolsSection.mapHeight).padding(.vertical, 6)
                if app.displays.count > 1 {
                    Picker("Màn chính", selection: Binding(
                        get: { app.displays.first(where: \.isMain)?.id ?? 0 },
                        set: { id in if let d = app.displays.first(where: { $0.id == id }) { app.makeMain(d) } })) {
                        ForEach(app.displays) { Text(ToolsSection.shortName($0)).tag($0.id) }
                    }
                    .accessibilityLabel("Màn chính (cửa sổ)")
                }
                if app.canMirror {
                    Toggle(isOn: Binding(get: { app.isMirroring }, set: { app.setMirroring($0) })) {
                        Text("Phản chiếu màn hình")
                        Text("Tắt: mỗi màn một desktop (mở rộng).")
                    }
                    .accessibilityLabel("Phản chiếu màn hình")
                }
            }
            let rotatable = app.displays.filter(\.canRotate)
            if MonitorPanel.canRotateAtAll, !rotatable.isEmpty {
                Section("Xoay màn hình") {
                    ForEach(rotatable) { d in
                        Picker(ToolsSection.shortName(d), selection: Binding(get: { d.rotation }, set: { app.rotate(d, to: $0) })) {
                            ForEach(Self.angles, id: \.self) { Text($0 == 0 ? "Chuẩn" : "\($0)°").tag($0) }
                        }
                        .accessibilityLabel("Xoay \(d.name) (công cụ)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Trang Chung

struct GeneralPaneV2: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) })) {
                    Text("Mở cùng máy")
                    Text("Chạy nền trên menu bar, không bật cửa sổ.")
                }
                .accessibilityLabel("Mở cùng máy")
            } header: {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
                    Text("Lumina").font(.title.weight(.bold)).foregroundStyle(.primary)
                    Text("Phiên bản \(LuminaCore.version)").font(.callout).foregroundStyle(.secondary)
                }
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
            Section {
                LabeledContent {
                    Button("Thoát") { NSApp.terminate(nil) }
                } label: {
                    Text("Thoát Lumina")
                    Text("Đóng cửa sổ này không tắt Lumina — mở lại từ icon trên menu bar hoặc Applications.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(.primary)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.bottom, 8)
    }
}
