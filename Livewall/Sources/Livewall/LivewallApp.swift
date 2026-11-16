import AppKit
import LivewallCore
import SwiftUI

@main
struct LivewallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let model = delegate.model
        let isVisible = !model.state.hidesMenuBarIcon
        MenuBarExtra(
            "Livewall",
            systemImage: "play.rectangle.on.rectangle",
            isInserted: Binding(get: { isVisible }, set: { model.setHidesMenuBarIcon(!$0) })
        ) {
            MenuBarContent(model: model, openWindow: delegate.showMainWindow, quit: delegate.quit)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(delegate.quitClosesWindow ? "Đóng cửa sổ" : "Thoát Livewall") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var mainWindow = MainWindowController(model: model)
    private var launchedAtLogin = false
    private var runningInstance: NSRunningApplication?
    private var quitsExplicitly = false
    private var isPoweringOff = false
    private var powerOffObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        runningInstance = earlierInstance()
    }

    private func earlierInstance() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        let launchDates = Dictionary(
            running.compactMap { app in app.launchDate.map { (app.processIdentifier, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let earlier = SingleInstance.earlierInstance(
            launchDates: launchDates,
            current: ProcessInfo.processInfo.processIdentifier
        )
        return running.first { $0.processIdentifier == earlier }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let runningInstance {
            if let url = runningInstance.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            quit()
            return
        }
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPoweringOff = true }
        }
        model.start()
        if !launchedAtLogin { showMainWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = runningInstance?.bundleURL {
            NSWorkspace.shared.open(urls, withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        model.add(urls)
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard quitAction(for: quitSource) == .closeWindow else { return .terminateNow }
        mainWindow.close()
        return .terminateCancel
    }

    /// What ⌘Q and the Dock's quit item do right now.
    var quitClosesWindow: Bool {
        quitAction(for: .ordinary) == .closeWindow
    }

    private func quitAction(for source: QuitPolicy.Source) -> QuitPolicy.Action {
        QuitPolicy.action(
            for: source,
            hasActiveWallpaper: model.state.displays.values.contains(where: \.isActive),
            showsMenuBarIcon: !model.state.hidesMenuBarIcon
        )
    }

    private var quitSource: QuitPolicy.Source {
        if quitsExplicitly { return .explicit }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let hasReason = event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
            || event?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        return isPoweringOff || hasReason ? .system : .ordinary
    }

    func quit() {
        quitsExplicitly = true
        NSApp.terminate(nil)
    }

    func showMainWindow() {
        mainWindow.show()
    }
}

/// AppKit owns this window so a login launch can stay in the background.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.isWindowVisible = true
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: RootView(model: model))
        hosting.sizingOptions = []

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Livewall"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        window.contentViewController = hosting
        window.setContentSize(CGSize(width: 1040, height: 700))
        window.contentMinSize = CGSize(width: 820, height: 560)
        window.center()
        window.setFrameAutosaveName("Main")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.isWindowVisible = false
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window, window.isVisible else { return }
        model.isWindowVisible = window.occlusionState.contains(.visible)
    }
}
