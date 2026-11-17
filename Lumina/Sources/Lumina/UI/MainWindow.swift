import AppKit
import LuminaCore
import SwiftUI

/// Cửa sổ Lumina — mở khi bấm Lumina.app trong Applications (hoặc nút cửa sổ trên popover).
///
/// Đồng bộ: cửa sổ và popover dùng chung một `AppState` (`Shared.app`), nên đổi ở đâu cũng hiện
/// ngay ở chỗ kia. Mỗi nơi có `PanelLayout` riêng vì đó chỉ là trạng thái đóng/mở của giao diện.
///
/// Khi cửa sổ mở, app hiện ở Dock và có menu (⌘W, ⌘Q, ⌘-Tab); đóng cửa sổ thì trở lại chỉ chạy nền
/// trên menu bar.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    let layout: PanelLayout = {
        let l = PanelLayout()
        l.toolsOpen = true
        return l
    }()

    /// Mục đang chọn ở thanh bên (giữ ngoài view để mở cửa sổ thẳng vào một mục).
    let nav = WindowNav()

    var isVisible: Bool { window?.isVisible == true }
    var windowContentView: NSView? { window?.contentView }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        AppMenu.install()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() { window?.close() }

    private func makeWindow() -> NSWindow {
        let root = MainWindowView()
            .environment(Shared.app)
            .environment(layout)
            .environment(nav)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: root)
        window.title = "Lumina"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 860, height: 640))
        window.center()
        window.setFrameAutosaveName("LuminaMainWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Không còn cửa sổ: bỏ Dock icon, chạy nền như cũ.
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Menu ứng dụng tối thiểu (chỉ hiện khi cửa sổ đang mở).
@MainActor
enum AppMenu {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Lumina")
        appMenu.addItem(withTitle: "Giới thiệu Lumina", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ẩn Lumina", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Thoát Lumina", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Cửa sổ")
        windowMenu.addItem(withTitle: "Đóng", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Thu nhỏ", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}

// MARK: - Giao diện cửa sổ

@MainActor @Observable
final class WindowNav {
    var selection: WindowPane?
}

enum WindowPane: Hashable {
    case display(CGDirectDisplayID)
    case tools
    case general
}

struct MainWindowView: View {
    @Environment(AppState.self) private var app
    @Environment(WindowNav.self) private var nav

    private var selection: WindowPane? {
        get { nav.selection }
        nonmutating set { nav.selection = newValue }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { nav.selection }, set: { nav.selection = $0 })) {
                Section("Màn hình") {
                    ForEach(app.displays) { d in
                        HStack(spacing: 10) {
                            Image(systemName: d.isBuiltIn ? "laptopcomputer" : "display")
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ToolsSection.shortName(d)).lineLimit(1)
                                Text(d.current.resolution.label + (d.isMain ? " · màn chính" : ""))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(WindowPane.display(d.id))
                        .accessibilityLabel(d.name)
                    }
                }
                Section("Lumina") {
                    Label("Công cụ", systemImage: "wrench.and.screwdriver").tag(WindowPane.tools)
                    Label("Chung", systemImage: "gearshape").tag(WindowPane.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ScrollView {
                detail
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { banners }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            app.registry.reload()
            app.refreshBrightness()
            app.refreshLoginItem()
            if selection == nil { selection = app.displays.first.map { .display($0.id) } ?? .tools }
        }
        .onChange(of: app.displays.map(\.id)) {
            // Màn đang chọn bị rút (hoặc đang phản chiếu): chuyển sang màn đầu tiên.
            if case .display(let id) = selection, !app.displays.contains(where: { $0.id == id }) {
                selection = app.displays.first.map { .display($0.id) } ?? .tools
            }
        }
        .animation(PopoverView.expand, value: app.pending != nil)
        .animation(PopoverView.expand, value: app.errorMessage)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .display(let id):
            if let d = app.displays.first(where: { $0.id == id }) {
                DisplayPane(display: d)
            }
        case .tools:
            VStack(alignment: .leading, spacing: 12) {
                PaneTitle(title: "Công cụ", subtitle: "Ngăn ngủ, sắp xếp, phản chiếu và xoay màn hình")
                ToolsSection().padding(.horizontal, -10).padding(.top, -8)
            }
        case .general:
            GeneralPane()
        case nil:
            EmptyView()
        }
    }

    private var banners: some View {
        VStack(spacing: 8) {
            if let p = app.pending {
                PendingBanner(change: p).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let e = app.errorMessage {
                ErrorBanner(message: e).transition(.opacity)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 24)
        .padding(.bottom, app.pending == nil && app.errorMessage == nil ? 0 : 16)
        .frame(maxWidth: .infinity)
    }
}

private struct PaneTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Một màn: thẻ độ sáng/độ phân giải/tỉ lệ (chung với popover) + thẻ bố cục (màn chính, xoay).
private struct DisplayPane: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot

    private static let angles = [0, 90, 180, 270]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: display.name, subtitle: subtitle)
            DisplayCardView(display: display)
            VStack(alignment: .leading, spacing: 12) {
                Text("Bố cục").font(.system(size: 13, weight: .semibold))
                if app.displays.count > 1 {
                    HStack {
                        Text("Màn chính").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        if display.isMain {
                            Label("Đang là màn chính", systemImage: "menubar.rectangle")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            Button("Đặt làm màn chính") { app.makeMain(display) }
                                .controlSize(.small)
                                .accessibilityLabel("Đặt \(display.name) làm màn chính")
                        }
                    }
                }
                if display.canRotate, MonitorPanel.canRotateAtAll {
                    HStack {
                        Text("Xoay").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        SegmentedChips(options: Self.angles.map { "\($0)°" },
                                       selected: Self.angles.firstIndex(of: display.rotation),
                                       itemWidth: 44,
                                       accessibilityLabel: { "Xoay \(display.name) \(Self.angles[$0]) độ (cửa sổ)" }) {
                            app.rotate(display, to: Self.angles[$0])
                        }
                    }
                }
                if app.canMirror {
                    Toggle("Phản chiếu màn chính lên mọi màn", isOn: Binding(
                        get: { app.isMirroring }, set: { app.setMirroring($0) }))
                        .glassSwitch()
                }
            }
            .platter()
            NitsCard(display: display)
            if !display.isBuiltIn { ColorCard(display: display) }
        }
    }

    private var subtitle: String {
        var parts = [display.isBuiltIn ? "Màn tích hợp" : "Màn ngoài"]
        if let d = display.diagonal { parts.append(String(format: "%.1f″", d).replacingOccurrences(of: ".", with: ",")) }
        parts.append("\(display.current.pixelWidth) × \(display.current.pixelHeight) điểm ảnh")
        if display.isMain { parts.append("màn chính") }
        return parts.joined(separator: " · ")
    }
}

/// Màu của màn ngoài cho tương xứng với màn Mac: gam màu (hồ sơ Display P3) và điểm trắng (R/G/B qua DDC).
/// Công tắc HDR nằm ở đầu thẻ màn (chung với popover).
private struct ColorCard: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot

    var body: some View {
        let _ = app.colorProfileRevision
        let profile = ColorService.profileName(display.id) ?? "—"
        let isP3 = ColorService.usesDisplayP3(display.id)
        VStack(alignment: .leading, spacing: 12) {
            Text("Màu").font(.system(size: 13, weight: .semibold))
            HStack {
                Text("Hồ sơ màu").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if isP3 {
                    Label("\(profile) — cùng gam màu với Mac", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(profile).font(.system(size: 12))
                    Button("Dùng Display P3 như Mac") { app.useDisplayP3(display) }.controlSize(.small)
                }
            }
            if let wb = app.whiteBalance[display.id] {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Điểm trắng").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Khôi phục") { app.restoreWhiteBalance(display) }
                            .controlSize(.small)
                            .disabled(app.originalWhiteBalance(display) == nil)
                    }
                    gainRow("Đỏ", value: wb.red, tint: .red) { var w = wb; w.red = $0; app.setWhiteBalance(w, for: display) }
                    gainRow("Lục", value: wb.green, tint: .green) { var w = wb; w.green = $0; app.setWhiteBalance(w, for: display) }
                    gainRow("Lam", value: wb.blue, tint: .blue) { var w = wb; w.blue = $0; app.setWhiteBalance(w, for: display) }
                }
                Text("Để hai màn cạnh nhau, mở một trang trắng ở giữa, kéo Đỏ/Lục/Lam đến khi trắng của màn này giống trắng của Mac (Mac dùng D65 ≈ 6500K). Ám vàng: giảm Đỏ hoặc tăng Lam; ám xanh: ngược lại.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if app.brightness[display.id]?.kind == .hardware {
                ProgressView().controlSize(.small)
            }
        }
        .platter()
        .onAppear { app.refreshWhiteBalance(display) }
    }

    private func gainRow(_ title: String, value: Int, tint: Color, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint.opacity(0.8)).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12)).frame(width: 30, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }), in: 0...100, step: 1)
                .accessibilityLabel("\(title) \(display.name)")
            Text("\(value)").font(.system(size: 12)).monospacedDigit().frame(width: 28, alignment: .trailing)
        }
    }
}

/// Độ sáng thật (ước lượng): nit tối đa/tối thiểu của màn, mức bù khi đồng bộ.
private struct NitsCard: View {
    @Environment(AppState.self) private var app
    let display: DisplaySnapshot

    var body: some View {
        let p = app.profile(for: display)
        let isSource = display.id == app.syncSource?.id
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Độ sáng thật").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let n = app.nits(for: display) {
                    Text("≈ \(Int(n.rounded())) nit").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            nitsRow("Tối đa", value: p.maxNits, range: 100...2000, step: 50) { v in app.updateProfile(display) { $0.maxNits = v } }
            nitsRow("Tối thiểu", value: p.minNits, range: 0...200, step: 5) { v in app.updateProfile(display) { $0.minNits = v } }
            if app.canSyncBrightness {
                Toggle("Đồng bộ độ sáng giữa các màn", isOn: Binding(get: { app.brightnessSync },
                                                                   set: { app.brightnessSync = $0 }))
                    .glassSwitch()
                if !isSource {
                    HStack {
                        Text("Bù so với \(app.syncSource.map(ToolsSection.shortName) ?? "màn chuẩn")")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text(p.ratio == 1 ? "bằng nhau" : String(format: "%+.0f%%", (p.ratio - 1) * 100))
                            .font(.system(size: 12)).monospacedDigit()
                        Button("Đặt lại") { app.updateProfile(display) { $0.ratio = 1 } }
                            .controlSize(.small).disabled(p.ratio == 1)
                    }
                }
            }
            Text(isSource
                 ? "Màn chuẩn: các màn khác bám theo số nit của màn này (kể cả khi chỉnh bằng phím độ sáng)."
                 : "Số nit là ước lượng theo thông số hãng. Khi đang đồng bộ, kéo thanh độ sáng của màn này cho khớp mắt — Lumina nhớ mức bù đó.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Về mặc định") { app.resetProfile(display) }
                    .controlSize(.small)
                    .disabled(app.nitsProfiles[display.identity.key] == nil)
            }
        }
        .platter()
    }

    private func nitsRow(_ title: String, value: Double, range: ClosedRange<Double>, step: Double,
                         set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value)) nit").font(.system(size: 12)).monospacedDigit()
            Stepper("", value: Binding(get: { value }, set: set), in: range, step: step)
                .labelsHidden()
                .accessibilityLabel("\(title) \(display.name)")
        }
    }
}

private struct GeneralPane: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: "Chung", subtitle: "Lumina \(LuminaCore.version)")
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Mở cùng máy", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                    .glassSwitch()
                Text("Lumina chạy nền trên menu bar. Đóng cửa sổ này không tắt app; mở lại từ icon trên menu bar hoặc từ Applications.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .platter()
            HStack {
                Spacer()
                Button("Thoát Lumina") { NSApp.terminate(nil) }
            }
        }
    }
}
