import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let command = args.first, !command.hasPrefix("-") {
            exit(CLI.run(args))   // chế độ dòng lệnh, không mở giao diện
        }
        // Vòng đời AppKit thuần, không dùng SwiftUI App: app không có scene/cửa sổ nào.
        // (Trước đây `Settings { EmptyView() }` làm macOS mở một cửa sổ "Lumina Settings" trống
        // mỗi khi bấm mở lại app trong Applications.) Icon menu bar + popover do StatusItemController quản lý.
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // không hiện ở Dock, giống LSUIElement
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
enum Shared {
    static let app = AppState()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?
    @MainActor static var statusItem: StatusItemController?

    /// Mở cùng máy (login item) thì chỉ chạy nền; người dùng tự mở app thì hiện cửa sổ.
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// Bấm mở Lumina.app trong Applications khi app đang chạy: mở cửa sổ Lumina.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            AppDelegate.statusItem?.close()
            MainWindowController.shared.show()
        }
        return false
    }

    /// Đóng cửa sổ không thoát app: vẫn chạy nền trên menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Cờ cho dev/kiểm thử:
    ///   --preview                         mở popover trong một cửa sổ thường
    ///   --snapshot <file.png> [--expand]  render popover ra PNG rồi thoát
    ///   --selftest-revert <id> <WxH>      đổi độ phân giải qua AppState, chụp thanh đếm ngược,
    ///                                     không bấm gì và kiểm tra tự hoàn tác sau 15 giây
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        MainActor.assumeIsolated {
            if !args.contains("--snapshot") || args.contains("--trace-popover") {
                AppDelegate.statusItem = StatusItemController(app: Shared.app)
            }
            if let i = args.firstIndex(of: "--selftest-revert"), args.count > i + 2 {
                DevTools.selfTestRevert(displayArg: args[i + 1], spec: args[i + 2],
                                        snapshot: args.firstIndex(of: "--snapshot").flatMap { args[safe: $0 + 1] })
                return
            }
            if let i = args.firstIndex(of: "--menubar-preview"), let path = args[safe: i + 1] {
                DevTools.menuBarPreview(to: path)
                exit(0)
            }
            if args.contains("--sleep-test") {
                DevTools.sleepTest()
                return
            }
            if let i = args.firstIndex(of: "--window-snapshot"), let path = args[safe: i + 1] {
                DevTools.windowSnapshot(to: path, pane: args[safe: i + 2] ?? "display")
                return
            }
            if args.contains("--profile") {
                DevTools.profile()
                return
            }
            if args.contains("--color-test") {
                DevTools.colorTest()
                return
            }
            if args.contains("--sync-test") {
                DevTools.syncTest()
                return
            }
            if args.contains("--fit-test") {
                DevTools.fitTest()
                return
            }
            if args.contains("--window-test") {
                DevTools.windowSyncTest()
                return
            }
            if args.contains("--expand-test") {
                DevTools.expandTest()
                return
            }
            if args.contains("--tools-test") {
                DevTools.toolsClickTest()
                return
            }
            if let i = args.firstIndex(of: "--panel-snapshot"), let path = args[safe: i + 1] {
                DevTools.panelSnapshot(to: path)
                return
            }
            if let i = args.firstIndex(of: "--trace-popover"), let s = args[safe: i + 1].flatMap(Double.init) {
                DevTools.tracePopover(seconds: s)
                return
            }
            if let i = args.firstIndex(of: "--snapshot"), let path = args[safe: i + 1] {
                DevTools.snapshot(to: path, after: 2) { exit(0) }
                return
            }
        }
        // Người dùng tự mở app (không phải mở cùng máy, không phải cờ dev): hiện cửa sổ ngay.
        let devFlag = args.dropFirst().contains { $0.hasPrefix("--") }
        if !devFlag && !launchedAsLoginItem {
            MainActor.assumeIsolated { MainWindowController.shared.show() }
        }
        guard args.contains("--preview") else { return }
        MainActor.assumeIsolated {
            let host = NSHostingView(rootView: PopoverView().environment(Shared.app).environment(PanelLayout()))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Lumina — xem trước"
            window.contentView = host
            window.center()
            window.makeKeyAndOrderFront(nil)
            previewWindow = window
        }
    }
}

enum MenuBarIcon {
    /// Template 18 pt: cùng hình với icon app — khối ba cánh (trefoil): viền ngoài + lõi đặc,
    /// ba gân từ tâm ra ba cánh như góc một khối lập phương phát sáng.
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            draw()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Lumina"
        return img
    }()

    /// Ba cánh hướng lên, xuống-trái, xuống-phải (hệ toạ độ gốc trên-trái, y hướng xuống).
    /// Giống `trefoil(...)` trong scripts/make-icon.swift (icon app), để hai icon cùng một hình.
    static func trefoil(center c: NSPoint, tip R: CGFloat, notch r: CGFloat, tipHalf d: CGFloat, radius: CGFloat) -> NSBezierPath {
        var pts: [NSPoint] = []
        for k in 0..<3 {
            let th = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 3
            pts.append(NSPoint(x: c.x + R * cos(th - d), y: c.y + R * sin(th - d)))
            pts.append(NSPoint(x: c.x + R * cos(th + d), y: c.y + R * sin(th + d)))
            let nt = th + .pi / 3
            pts.append(NSPoint(x: c.x + r * cos(nt), y: c.y + r * sin(nt)))
        }
        let path = NSBezierPath()
        let n = pts.count
        path.move(to: NSPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for i in 0..<n { path.appendArc(from: pts[i], to: pts[(i + 1) % n], radius: radius) }
        path.close()
        return path
    }

    /// Vẽ trong hệ toạ độ 18×18, gốc trên-trái.
    static func draw() {
        NSColor.black.set()
        let c = NSPoint(x: 9, y: 9.7)
        let outer = trefoil(center: c, tip: 8.4, notch: 4.2, tipHalf: 0.30, radius: 1.5)
        outer.lineWidth = 1.25
        outer.lineJoinStyle = .round
        outer.stroke()
        trefoil(center: c, tip: 4.7, notch: 2.35, tipHalf: 0.31, radius: 0.8).fill()
    }
}
