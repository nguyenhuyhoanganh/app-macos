import AppKit
import AVFoundation
import LivewallCore
import QuartzCore

/// One display's wallpaper: a video window at desktop level.
@MainActor
final class WallpaperController {
    let displayKey: String
    private(set) var wallpaperID: UUID?
    var isCovered = false

    private let window: NSWindow
    private var stage: Stage?
    private var url: URL?
    private var audioURL: URL?
    private var hasAudio = false
    private var presentation: UUID?
    private var wantsPlayback = false
    private var placement = Placement(crop: .none, videoSize: .zero)

    /// Where a video sits so bars baked into it fall outside the screen.
    struct Placement: Equatable {
        var crop: VideoCrop
        var videoSize: CGSize

        func frame(in bounds: CGRect) -> CGRect {
            guard videoSize.width > 0, videoSize.height > 0 else { return bounds }
            return crop.playerFrame(videoSize: videoSize, in: bounds)
        }
    }

    @MainActor
    private final class Stage {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let layer: AVPlayerLayer
        var placement: Placement
        var readiness: NSKeyValueObservation?

        init(asset: AVAsset, placement: Placement) {
            self.placement = placement
            let item = AVPlayerItem(asset: asset)
            player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: item)
            layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
        }

        func tearDown() {
            readiness = nil
            player.pause()
            looper.disableLooping()
            player.removeAllItems()
            layer.removeFromSuperlayer()
        }
    }

    init(displayKey: String, frame: CGRect) {
        self.displayKey = displayKey
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(frame, display: false)

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView?.layer?.masksToBounds = true

        window.orderFront(nil)
    }

    func load(url: URL, audioURL: URL?, wallpaperID: UUID, volume: Double, placement: Placement) {
        self.placement = placement
        guard url != self.url || audioURL != self.audioURL else {
            if let stage, stage.placement != placement {
                stage.placement = placement
                layOut(stage)
            }
            return
        }
        self.wallpaperID = wallpaperID
        self.url = url
        self.audioURL = audioURL
        present(url: url, volume: volume)
    }

    private func present(url: URL, volume: Double) {
        hasAudio = Self.isAudible(volume)
        let request = UUID()
        presentation = request
        Task {
            let asset = await VideoAsset.make(url: url, audioURL: audioURL, withAudio: hasAudio)
            guard presentation == request else { return }
            show(Stage(asset: asset, placement: placement), volume: volume)
        }
    }

    private func show(_ next: Stage, volume: Double) {
        let previous = stage
        stage = next
        next.player.volume = Float(volume)

        guard let host = window.contentView?.layer else { return }
        next.layer.frame = next.placement.frame(in: host.bounds)
        next.layer.opacity = 0
        host.addSublayer(next.layer)

        next.readiness = next.layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak next] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in
                guard let self, let next else { return }
                self.reveal(next, replacing: previous)
            }
        }
        if wantsPlayback { next.player.play() }
    }

    private func reveal(_ next: Stage, replacing previous: Stage?) {
        next.readiness = nil
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        CATransaction.setCompletionBlock {
            Task { @MainActor in previous?.tearDown() }
        }
        next.layer.opacity = 1
        CATransaction.commit()
    }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        if playing {
            stage?.player.play()
        } else {
            stage?.player.pause()
        }
    }

    func setVolume(_ volume: Double) {
        if Self.isAudible(volume) != hasAudio, let url {
            present(url: url, volume: volume)
        } else {
            stage?.player.volume = Float(volume)
        }
    }

    private static func isAudible(_ volume: Double) -> Bool {
        volume >= 0.01
    }

    /// macOS draws a gradient behind the menu bar one level above the desktop icons.
    /// Only a window above that level hides it, so the video then sits at the widgets'
    /// level, ordered behind them.
    func setHidesDesktopIcons(_ hides: Bool) {
        let level = hides
            ? CGWindowLevelForKey(.desktopIconWindow) + 2
            : CGWindowLevelForKey(.desktopWindow)
        window.level = NSWindow.Level(Int(level))
        window.orderBack(nil)
    }

    func move(to frame: CGRect) {
        window.setFrame(frame, display: true)
        if let stage { layOut(stage) }
    }

    private func layOut(_ stage: Stage) {
        guard let host = window.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.layer.frame = stage.placement.frame(in: host.bounds)
        CATransaction.commit()
    }

    func close() {
        presentation = nil
        stage?.tearDown()
        stage = nil
        window.close()
    }
}
