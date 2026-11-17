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

    /// Chỉ cho ảnh chụp kiểm thử: kéo cửa sổ cao ra để thấy hết trang.
    func setContentSizeForSnapshot(_ size: NSSize) { window?.setContentSize(size) }

    private func makeWindow() -> NSWindow {
        let root = MainWindowView()
            .environment(Shared.app)
            .environment(layout)
            .environment(nav)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: root)
        window.title = "Lumina"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 920, height: 700))
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
                        SidebarRow(title: ToolsSection.shortName(d),
                                   subtitle: d.current.resolution.label + (d.isMain ? " · màn chính" : ""),
                                   symbol: d.isBuiltIn ? "laptopcomputer" : "display",
                                   colors: [Color(red: 0.35, green: 0.66, blue: 1), Color(red: 0.18, green: 0.45, blue: 0.88)])
                            .tag(WindowPane.display(d.id))
                            .accessibilityLabel(d.name)
                    }
                }
                Section("Lumina") {
                    SidebarRow(title: "Công cụ", symbol: "wrench.and.screwdriver.fill",
                               colors: [Color(red: 1, green: 0.68, blue: 0.27), Color(red: 0.95, green: 0.48, blue: 0.1)])
                        .tag(WindowPane.tools)
                    SidebarRow(title: "Chung", symbol: "gearshape.fill",
                               colors: [Color(white: 0.62), Color(white: 0.44)])
                        .tag(WindowPane.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            // Mỗi trang là một Form .grouped (tự cuộn) như Cài đặt hệ thống.
            detail
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .safeAreaInset(edge: .bottom) { banners }
        }
        .frame(minWidth: 760, minHeight: 560)
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
                DisplayPaneV2(display: d).id(d.id)
            }
        case .tools:
            ToolsPaneV2()
        case .general:
            GeneralPaneV2()
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
        .frame(maxWidth: 600)
        .padding(.horizontal, 28)
        .padding(.bottom, app.pending == nil && app.errorMessage == nil ? 0 : 16)
        .frame(maxWidth: .infinity)
    }
}

/// Dòng ở thanh bên kiểu Cài đặt hệ thống: ô icon màu bo góc + tên (+ dòng phụ).
private struct SidebarRow: View {
    let title: String
    var subtitle: String?
    let symbol: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
