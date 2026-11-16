import AppKit
import AVFoundation
import LivewallCore
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var library: WallpaperLibrary
    private(set) var state: AppState
    private(set) var displays: [DisplayInfo] = []
    private(set) var playing: Set<String> = []
    private(set) var importing = 0
    private(set) var renderProgress: Double?
    private(set) var usage: StorageUsage?
    private(set) var startsAtLogin = LoginItem.isEnabled
    /// The window's live preview is a second decode, so it runs only while visible.
    var isWindowVisible = false
    var selectedDisplay: String?
    var filter = WallpaperFilter()
    var notice: String?

    @ObservationIgnored private let engine = WallpaperEngine()
    @ObservationIgnored private let libraryStore = JSONStore<WallpaperLibrary>(url: Paths.library)
    @ObservationIgnored private let stateStore = JSONStore<AppState>(url: Paths.state)
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init() {
        Paths.prepare()
        library = libraryStore.load() ?? WallpaperLibrary()
        state = stateStore.load() ?? AppState()
    }

    func start() {
        _ = removeOrphans()
        engine.onEnvironmentChange = { [weak self] in self?.refreshPlayback() }
        engine.onDisplaysChange = { [weak self] in self?.refreshDisplays() }
        engine.start()
        refreshDisplays()
        Task {
            await addMissingLoopAudio()
            await addMissingCrops()
        }
    }

    // MARK: Displays

    var currentDisplay: DisplayInfo? {
        displays.first { $0.key == selectedDisplay } ?? displays.first
    }

    func wallpaper(on display: String) -> Wallpaper? {
        state.config(for: display).wallpaperID.flatMap(library.wallpaper(id:))
    }

    func isShowing(_ wallpaper: Wallpaper) -> Bool {
        guard let currentDisplay else { return false }
        return state.config(for: currentDisplay.key).wallpaperID == wallpaper.id
    }

    func select(_ display: DisplayInfo) {
        selectedDisplay = display.key
        if displays.count > 1, let screen = NSScreen.screen(forKey: display.key) {
            DisplayHighlight.flash(screen)
        }
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.map(\.displayInfo)
        if currentDisplay?.key != selectedDisplay { selectedDisplay = currentDisplay?.key }
        adoptNewDisplays()
        applyToEngine()
    }

    /// A monitor plugged in for the first time shows the main display's wallpaper.
    private func adoptNewDisplays() {
        guard
            let adoption = state.adoption(connected: displays.map(\.key)),
            let wallpaper = library.wallpaper(id: adoption.wallpaper)
        else { return }
        adoption.displays.forEach { assign(wallpaper, to: $0) }
        saveState()
    }

    private func applyToEngine() {
        engine.sync(state: state, library: library)
        refreshPlayback()
    }

    private func refreshPlayback() {
        playing = engine.updatePlayback(energy: state.energy)
    }

    // MARK: Status

    func status(of display: String) -> String {
        let config = state.config(for: display)
        guard config.wallpaperID != nil else { return "Chưa có hình nền" }
        guard config.isEnabled else { return "Đang tắt" }
        if playing.contains(display) { return "Đang phát" }
        if engine.displaysAsleep { return "Tạm dừng khi màn hình ngủ" }
        if engine.controllers[display]?.isCovered == true, state.energy.pauseWhenCovered {
            return "Tạm dừng vì desktop bị che"
        }
        return "Tạm dừng để tiết kiệm pin"
    }

    // MARK: Applying wallpapers

    func apply(_ wallpaper: Wallpaper) {
        guard let key = currentDisplay?.key else { return }
        apply(wallpaper, to: key)
    }

    func applyToAllDisplays(_ wallpaper: Wallpaper) {
        displays.forEach { apply(wallpaper, to: $0.key) }
    }

    private func apply(_ wallpaper: Wallpaper, to display: String) {
        assign(wallpaper, to: display)
        saveState()
        applyToEngine()
    }

    private func assign(_ wallpaper: Wallpaper, to display: String) {
        let screen = NSScreen.screen(forKey: display)
        let previous = screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        state.assign(wallpaper.id, to: display, previousSystemImage: previous)
        Task { await setStillImage(of: wallpaper, on: display) }
    }

    /// Keeps Mission Control and quitting from revealing the old picture.
    private func setStillImage(of wallpaper: Wallpaper, on display: String) async {
        guard let screen = NSScreen.screen(forKey: display) else { return }
        let url = Paths.desktopImages.appendingPathComponent(wallpaper.stillFileName)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                let video = Paths.videos.appendingPathComponent(wallpaper.fileName)
                let image = try await VideoImporter.frame(of: video, at: wallpaper.coverTime)
                try VideoImporter.write(VideoImporter.cropped(image, by: wallpaper.crop ?? .none), to: url, as: .png)
            }
            try setDesktopImage(url, on: screen)
        } catch {
            show("Không đặt được ảnh nền hệ thống.")
        }
    }

    private func setDesktopImage(_ url: URL, on screen: NSScreen) throws {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ])
    }

    func removeWallpaper(from display: String) {
        let restored = state.clear(display)
        saveState()
        applyToEngine()
        restore(restored, on: display)
    }

    private func restore(_ image: URL?, on display: String) {
        guard let image, let screen = NSScreen.screen(forKey: display) else { return }
        try? setDesktopImage(image, on: screen)
    }

    func setEnabled(_ enabled: Bool, for display: String) {
        state.setEnabled(enabled, for: display)
        saveState()
        applyToEngine()
    }

    func setVolume(_ volume: Double, for display: String) {
        state.setVolume(volume, for: display)
        engine.controllers[display]?.setVolume(volume)
        saveState()
    }

    // MARK: Library

    func add(_ urls: [URL]) {
        importing += urls.count
        Task {
            for url in urls {
                await importVideo(url)
                importing -= 1
            }
        }
    }

    private func importVideo(_ url: URL) async {
        let probe = await VideoImporter.inspect(url)
        var warning: VideoWarning?
        switch VideoCheck.evaluate(probe.facts) {
        case .rejected(let reason):
            show(message(for: reason, file: url.lastPathComponent))
            return
        case .accepted(let found):
            warning = found
        }

        var copied: [URL] = []
        do {
            let hash = try await VideoImporter.sha256(of: url)
            guard library.wallpaper(withHash: hash) == nil else {
                show("Video này đã có trong thư viện.")
                return
            }
            guard DiskSpace.hasRoom(for: fileSize(at: url), available: availableSpace()) else {
                show("Ổ đĩa không đủ chỗ để thêm \(url.lastPathComponent).")
                return
            }
            let id = UUID()
            let fileName = "\(id.uuidString).\(url.pathExtension.lowercased())"
            let destination = Paths.videos.appendingPathComponent(fileName)
            copied.append(destination)
            try await VideoImporter.copyIntoLibrary(url, as: destination)

            let wallpaper = Wallpaper(
                id: id,
                name: url.deletingPathExtension().lastPathComponent,
                fileName: fileName,
                contentHash: hash,
                duration: probe.duration,
                width: probe.facts.width,
                height: probe.facts.height,
                hasAudio: probe.hasAudio,
                coverTime: min(1, probe.duration / 2),
                crop: await VideoImporter.crop(of: destination, duration: probe.duration)
            )
            copied.append(Self.coverURL(of: wallpaper))
            try await writeCover(for: wallpaper)
            library.add(wallpaper)
            saveLibrary()
            if warning == .lowResolution {
                show("Video có độ phân giải thấp nên có thể bị mờ.")
            }
        } catch {
            copied.forEach { try? FileManager.default.removeItem(at: $0) }
            show("Không thêm được \(url.lastPathComponent).")
        }
    }

    private func message(for rejection: VideoRejection, file: String) -> String {
        switch rejection {
        case .unsupportedFormat: "\(file): định dạng này không phát được."
        case .noVideoTrack: "\(file): tệp không có hình ảnh."
        case .corruptedFrames: "\(file): video có khung hình bị lỗi."
        }
    }

    static func coverURL(of wallpaper: Wallpaper) -> URL {
        Paths.covers.appendingPathComponent(wallpaper.coverFileName)
    }

    private func writeCover(for wallpaper: Wallpaper) async throws {
        let video = Paths.videos.appendingPathComponent(wallpaper.fileName)
        let image = try await VideoImporter.frame(of: video, at: wallpaper.coverTime, maxWidth: 960)
        try VideoImporter.write(image, to: Self.coverURL(of: wallpaper), as: .jpeg)
    }

    func setLoopMode(_ mode: LoopMode, of wallpaper: Wallpaper) {
        guard mode != wallpaper.loopMode, renderProgress == nil else { return }
        Task { await setLoopsBothWays(mode == .backAndForth, for: wallpaper) }
    }

    func update(_ wallpaper: Wallpaper, loopMode: LoopMode) {
        let previous = library.wallpaper(id: wallpaper.id)
        let coverChanged = previous?.coverTime != wallpaper.coverTime
        let loopChanged = loopMode != wallpaper.loopMode
        guard coverChanged || loopChanged else {
            library.update(wallpaper)
            saveLibrary()
            return
        }
        Task {
            if coverChanged { try? await writeCover(for: wallpaper) }
            library.update(wallpaper)
            saveLibrary()
            if coverChanged {
                for display in displays where state.config(for: display.key).wallpaperID == wallpaper.id {
                    await setStillImage(of: wallpaper, on: display.key)
                }
                if let previous {
                    try? FileManager.default.removeItem(
                        at: Paths.desktopImages.appendingPathComponent(previous.stillFileName)
                    )
                }
            }
            if loopChanged { await setLoopsBothWays(loopMode == .backAndForth, for: wallpaper) }
        }
    }

    private func setLoopsBothWays(_ enabled: Bool, for wallpaper: Wallpaper) async {
        var updated = wallpaper
        let replaced = wallpaper.pingPongFileName
        if enabled {
            guard renderProgress == nil else {
                show("Đang tạo một vòng lặp khác, bạn thử lại sau nhé.")
                return
            }
            let size = fileSize(at: Paths.videos.appendingPathComponent(wallpaper.fileName))
            guard DiskSpace.hasRoom(for: DiskSpace.estimatedLoopSize(ofVideo: size), available: availableSpace()) else {
                show("Ổ đĩa không đủ chỗ để tạo vòng lặp này.")
                return
            }
            guard let name = await renderLoop(of: wallpaper) else {
                show("Không tạo được vòng lặp cho video này.")
                return
            }
            updated.pingPongFileName = name
            updated.pingPongAudioFileName = await renderLoopAudio(of: updated)
        } else {
            updated.pingPongFileName = nil
            updated.pingPongAudioFileName = nil
        }
        library.update(updated)
        saveLibrary()
        applyToEngine()
        if !enabled {
            for name in [replaced, wallpaper.pingPongAudioFileName].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: Paths.videos.appendingPathComponent(name))
            }
        }
    }

    private func renderLoopAudio(of wallpaper: Wallpaper) async -> String? {
        guard wallpaper.hasAudio, let loop = wallpaper.pingPongFileName else { return nil }
        let name = "\(wallpaper.id.uuidString)-loop.caf"
        let source = Paths.videos.appendingPathComponent(wallpaper.fileName)
        let video = Paths.videos.appendingPathComponent(loop)
        let destination = Paths.videos.appendingPathComponent(name)
        do {
            try await Task.detached(priority: .utility) {
                let duration = try await AVURLAsset(url: video).load(.duration).seconds
                try await AudioLoopRenderer.render(from: source, to: destination, loopDuration: duration)
            }.value
            return name
        } catch {
            return nil
        }
    }

    /// Loops rendered before they had sound only need this step, not a new video.
    private func addMissingLoopAudio() async {
        for wallpaper in library.items where wallpaper.pingPongFileName != nil && !wallpaper.playsAudio {
            guard let name = await renderLoopAudio(of: wallpaper) else { continue }
            var updated = wallpaper
            updated.pingPongAudioFileName = name
            library.update(updated)
            saveLibrary()
            applyToEngine()
        }
    }

    /// Videos imported before bars were detected are checked once.
    private func addMissingCrops() async {
        for wallpaper in library.items where wallpaper.crop == nil {
            let source = Paths.videos.appendingPathComponent(wallpaper.fileName)
            let crop = await VideoImporter.crop(of: source, duration: wallpaper.duration)
            // The analysis takes a while; keep any edit made meanwhile.
            guard var updated = library.wallpaper(id: wallpaper.id) else { continue }
            updated.crop = crop
            library.update(updated)
            saveLibrary()
            guard updated.crop?.isEmpty == false else { continue }
            applyToEngine()
            for display in displays where state.config(for: display.key).wallpaperID == updated.id {
                await setStillImage(of: updated, on: display.key)
            }
        }
    }

    private func renderLoop(of wallpaper: Wallpaper) async -> String? {
        let name = "\(wallpaper.id.uuidString)-loop.mp4"
        let source = Paths.videos.appendingPathComponent(wallpaper.fileName)
        let destination = Paths.videos.appendingPathComponent(name)
        renderProgress = 0
        defer { renderProgress = nil }
        do {
            try await Task.detached(priority: .utility) {
                try await PingPongRenderer.render(from: source, to: destination) { value in
                    Task { @MainActor [weak self] in
                        if self?.renderProgress != nil { self?.renderProgress = value }
                    }
                }
            }.value
            return name
        } catch {
            return nil
        }
    }

    func delete(_ wallpaper: Wallpaper) {
        let restored = state.removeWallpaper(wallpaper.id)
        library.remove(wallpaper.id)
        saveState()
        saveLibrary()
        applyToEngine()
        restored.forEach { restore($0.value, on: $0.key) }

        let manager = FileManager.default
        let stills = (try? manager.contentsOfDirectory(at: Paths.desktopImages, includingPropertiesForKeys: nil)) ?? []
        let loop = [wallpaper.pingPongFileName, wallpaper.pingPongAudioFileName]
            .compactMap { $0 }
            .map(Paths.videos.appendingPathComponent)
        let files = stills.filter { $0.lastPathComponent.hasPrefix(wallpaper.id.uuidString) } + loop
            + [Paths.videos.appendingPathComponent(wallpaper.fileName), Self.coverURL(of: wallpaper)]
        files.forEach { try? manager.removeItem(at: $0) }
    }

    // MARK: Storage

    func refreshUsage() async {
        let library = library
        usage = await Task.detached(priority: .utility) { StorageUsage.measure(library: library) }.value
    }

    func cleanUp() async {
        let result = removeOrphans()
        await refreshUsage()
        show(result.message)
    }

    /// Runs at launch, before anything can be writing into the library, and from
    /// Settings, which only offers it while nothing is importing or rendering.
    private func removeOrphans() -> CleanupResult {
        guard importing == 0, renderProgress == nil else { return CleanupResult() }
        let manager = FileManager.default
        let orphans = StorageAudit.orphans(
            in: StorageListing(
                videos: names(in: Paths.videos),
                covers: names(in: Paths.covers),
                stills: names(in: Paths.desktopImages)
            ),
            library: library,
            keeping: filesInUseOutsideTheLibrary()
        )

        var result = CleanupResult()
        func remove(_ url: URL) {
            result.freed += fileSize(at: url)
            try? manager.removeItem(at: url)
        }
        orphans.covers.forEach { remove(Paths.covers.appendingPathComponent($0)) }
        orphans.stills.forEach { remove(Paths.desktopImages.appendingPathComponent($0)) }
        for name in orphans.videos {
            let url = Paths.videos.appendingPathComponent(name)
            if StorageAudit.isRendered(name) {
                remove(url)
            } else if (try? manager.trashItem(at: url, resultingItemURL: nil)) != nil {
                result.videosMovedToTrash += 1
            }
        }
        return result
    }

    private func filesInUseOutsideTheLibrary() -> Set<String> {
        let desktop = NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        let remembered = state.displays.values.compactMap(\.systemImage)
        return Set((desktop + remembered).map(\.lastPathComponent))
    }

    private func names(in directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private func availableSpace() -> Int64 {
        let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        return (try? Paths.root.resourceValues(forKeys: [key]))?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    // MARK: Settings

    func setEnergy(_ energy: EnergySettings) {
        state.energy = energy
        saveState()
        refreshPlayback()
    }

    func setHidesDesktopIcons(_ hides: Bool) {
        state.hidesDesktopIcons = hides
        saveState()
        applyToEngine()
    }

    func setHidesMenuBarIcon(_ hides: Bool) {
        guard hides != state.hidesMenuBarIcon else { return }
        state.hidesMenuBarIcon = hides
        saveState()
    }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            show("Không đổi được khởi động cùng máy.")
        }
        startsAtLogin = LoginItem.isEnabled
    }

    // MARK: Persistence and messages

    private func saveState() {
        try? stateStore.save(state)
    }

    private func saveLibrary() {
        try? libraryStore.save(library)
    }

    func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
    }
}
