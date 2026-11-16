import AppKit
import LivewallCore

/// Keeps one controller per connected display and reacts to the system.
@MainActor
final class WallpaperEngine {
    let power = PowerMonitor()
    private(set) var displaysAsleep = false
    private(set) var controllers: [String: WallpaperController] = [:]

    /// Fired when anything that could change what should be playing happens.
    var onEnvironmentChange: (() -> Void)?
    /// Fired after the set of displays changed.
    var onDisplaysChange: (() -> Void)?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var coverTimer: Timer?
    private static let settleDelay: Duration = .milliseconds(500)

    func start() {
        power.onChange = { [weak self] in self?.onEnvironmentChange?() }
        power.start()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.setAsleep(true) }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.setAsleep(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.setAsleep(false) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.setAsleep(false) }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { engine in
            engine.afterSettling {
                engine.refreshCoverage()
                engine.onEnvironmentChange?()
            }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { engine in
            engine.afterSettling { engine.onDisplaysChange?() }
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (WallpaperEngine) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
        observers.append((center, token))
    }

    /// Spaces and display changes report positions before they have finished moving.
    private func afterSettling(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: Self.settleDelay)
            work()
        }
    }

    private func setAsleep(_ asleep: Bool) {
        displaysAsleep = asleep
        onEnvironmentChange?()
    }

    func sync(state: AppState, library: WallpaperLibrary) {
        let screens = Dictionary(
            NSScreen.screens.map { ($0.displayKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (key, controller) in controllers where screens[key] == nil || !state.config(for: key).isActive {
            controller.close()
            controllers[key] = nil
        }

        for (key, screen) in screens {
            let config = state.config(for: key)
            guard
                config.isActive,
                let id = config.wallpaperID,
                let wallpaper = library.wallpaper(id: id)
            else { continue }

            let controller = controllers[key] ?? makeController(key: key, frame: screen.frame)
            controller.move(to: screen.frame)
            controller.setHidesDesktopIcons(state.hidesDesktopIcons)
            controller.load(
                url: Paths.videos.appendingPathComponent(wallpaper.playbackFileName),
                audioURL: wallpaper.pingPongAudioFileName.map(Paths.videos.appendingPathComponent),
                wallpaperID: id,
                volume: config.volume,
                placement: WallpaperController.Placement(
                    crop: wallpaper.crop ?? .none,
                    videoSize: CGSize(width: wallpaper.width, height: wallpaper.height)
                )
            )
            controller.setVolume(config.volume)
        }
        updateCoverTimer()
    }

    private func makeController(key: String, frame: CGRect) -> WallpaperController {
        let controller = WallpaperController(displayKey: key, frame: frame)
        controllers[key] = controller
        return controller
    }

    /// The window server's occlusion state ignores full-screen Spaces, so this polls
    /// the window list instead. It only needs bounds, which require no permission.
    private func updateCoverTimer() {
        guard !controllers.isEmpty else {
            coverTimer?.invalidate()
            coverTimer = nil
            return
        }
        guard coverTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCoverage() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        coverTimer = timer
        refreshCoverage()
    }

    private func refreshCoverage() {
        let windows = Self.normalWindowFrames()
        var changed = false
        for (key, controller) in controllers {
            guard let screen = NSScreen.screen(forKey: key) else { continue }
            let covered = Coverage.isCovered(Self.windowListRect(of: screen.visibleFrame), by: windows)
            if covered != controller.isCovered {
                controller.isCovered = covered
                changed = true
            }
        }
        if changed { onEnvironmentChange?() }
    }

    private static func normalWindowFrames() -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard
                info[kCGWindowLayer as String] as? Int == 0,
                (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
    }

    /// The window list uses a top-left origin; AppKit screens use bottom-left.
    private static func windowListRect(of frame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Runs the policy for every display and returns the keys now playing.
    @discardableResult
    func updatePlayback(energy: EnergySettings) -> Set<String> {
        var playing = Set<String>()
        for (key, controller) in controllers {
            let shouldPlay = PlaybackPolicy.shouldPlay(
                hasActiveWallpaper: controller.wallpaperID != nil,
                displaysAsleep: displaysAsleep,
                isOccluded: controller.isCovered,
                power: power.status,
                energy: energy
            )
            controller.setPlaying(shouldPlay)
            if shouldPlay { playing.insert(key) }
        }
        return playing
    }
}
