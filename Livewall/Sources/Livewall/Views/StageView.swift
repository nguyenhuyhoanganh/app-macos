import AppKit
import AVFoundation
import LivewallCore
import SwiftUI

/// The video on stage, playing live, with a cover underneath for the first frames.
struct StageBackdrop: View {
    let wallpaper: Wallpaper?
    let isLive: Bool

    var body: some View {
        Color.black
            .overlay {
                if let wallpaper {
                    ZStack {
                        CoverImage(wallpaper: wallpaper).scaledToFill()
                        if isLive {
                            VideoPreview(url: Paths.videos.appendingPathComponent(wallpaper.playbackFileName))
                        }
                    }
                    .id(wallpaper.id)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.5), location: 0.62),
                        .init(color: .black.opacity(0.66), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 360)
            }
            .clipped()
            .animation(.easeInOut(duration: 0.45), value: wallpaper?.id)
    }
}

struct StageChrome: View {
    let model: AppModel
    let onStage: Wallpaper?
    let isPreviewing: Bool
    @Binding var hovered: Wallpaper?
    let add: () -> Void
    let edit: (Wallpaper) -> Void
    let delete: (Wallpaper) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            header.padding(.horizontal, 24)
            Shelf(model: model, hovered: $hovered, add: add, edit: edit, delete: delete)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                if model.displays.count > 1 {
                    DisplayMap(model: model)
                }
                Text(onStage?.name ?? "")
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 2)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
            }
            Spacer(minLength: 0)
            if !isPreviewing, let display = model.currentDisplay, model.wallpaper(on: display.key) != nil {
                DisplayControls(model: model, display: display)
            }
        }
    }

    private var subtitle: String {
        if isPreviewing { return "Bấm để đặt làm hình nền" }
        guard let display = model.currentDisplay else { return "" }
        let status = model.status(of: display.key)
        return model.displays.count > 1 ? "\(display.name) · \(status)" : status
    }
}

extension LoopMode {
    var title: String {
        switch self {
        case .continuous: "Nối tiếp"
        case .backAndForth: "Qua lại"
        }
    }

    var symbol: String {
        switch self {
        case .continuous: "repeat"
        case .backAndForth: "arrow.left.arrow.right"
        }
    }

    var explanation: String {
        switch self {
        case .continuous: "Hết video thì chạy lại từ đầu. Hợp với cảnh đi một chiều như đoàn tàu."
        case .backAndForth: "Video chạy xuôi rồi ngược nên không có cú nhảy. Tiếng vẫn chạy xuôi và được nối mờ."
        }
    }

    var other: LoopMode {
        self == .continuous ? .backAndForth : .continuous
    }
}

/// Everything about the current display, all in plain sight.
private struct DisplayControls: View {
    let model: AppModel
    let display: DisplayInfo

    var body: some View {
        let config = model.state.config(for: display.key)
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let wallpaper = model.wallpaper(on: display.key), config.isActive {
                    if wallpaper.playsAudio {
                        VolumeControl(volume: config.volume) { model.setVolume($0, for: display.key) }
                    }
                    Button(wallpaper.loopMode.title, systemImage: wallpaper.loopMode.symbol) {
                        model.setLoopMode(wallpaper.loopMode.other, of: wallpaper)
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .disabled(model.renderProgress != nil)
                    .help(wallpaper.loopMode.explanation)
                }
                Button(config.isEnabled ? "Tắt hình nền" : "Bật hình nền", systemImage: "power") {
                    model.setEnabled(!config.isEnabled, for: display.key)
                }
                .tint(config.isEnabled ? nil : .white)
                .help(config.isEnabled ? "Tắt hình nền" : "Bật hình nền")
                Button("Gỡ hình nền", systemImage: "xmark") {
                    model.removeWallpaper(from: display.key)
                }
                .help("Gỡ hình nền và khôi phục ảnh cũ")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
        }
    }
}

private struct VolumeControl: View {
    let volume: Double
    let change: @MainActor @Sendable (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(volume > 0 ? "Tắt tiếng" : "Bật tiếng",
                   systemImage: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                change(volume > 0 ? 0 : 0.5)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .contentTransition(.symbolEffect(.replace))
            Slider(value: Binding(get: { volume }, set: change), in: 0...1)
                .controlSize(.small)
                .tint(.white)
                .frame(width: 112)
                .accessibilityLabel("Âm lượng")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A miniature of System Settings' display arrangement.
private struct DisplayMap: View {
    let model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let frames = Dictionary(
                model.displays.map { ($0.key, $0.frame) },
                uniquingKeysWith: { first, _ in first }
            )
            let fitted = DisplayLayout.fit(frames, in: proxy.size)
            ForEach(model.displays) { display in
                if let rect = fitted[display.key] {
                    let isSelected = display.key == model.currentDisplay?.key
                    Button { model.select(display) } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white.opacity(isSelected ? 1 : 0.26))
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width - 3, height: rect.height - 3)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel(display.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(width: 124, height: 44)
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct Shelf: View {
    let model: AppModel
    @Binding var hovered: Wallpaper?
    let add: () -> Void
    let edit: (Wallpaper) -> Void
    let delete: (Wallpaper) -> Void

    @ViewState private var position = ScrollPosition(edge: .leading)
    @ViewState private var metrics = Metrics(offset: 0, scroll: ShelfScroll(contentWidth: 0, visibleWidth: 0))
    @ViewState private var wheel = WheelRedirect()

    private struct Metrics: Equatable {
        var offset: Double
        var scroll: ShelfScroll
    }

    private var items: [Wallpaper] { model.library.filtered(by: model.filter) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: add) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.14))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 92, height: 90)
                    .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thêm video")
            .help("Thêm video")

            if items.isEmpty {
                Text("Không có video phù hợp")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                strip
            }
        }
        .padding(12)
        .frame(height: 140, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var strip: some View {
        let edges = metrics.scroll.edges(at: metrics.offset)
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { wallpaper in
                    ShelfItem(
                        wallpaper: wallpaper,
                        isApplied: model.isShowing(wallpaper),
                        hovered: $hovered,
                        action: { model.apply(wallpaper) }
                    )
                    .contextMenu {
                        if model.displays.count > 1 {
                            Button("Đặt cho mọi màn hình") { model.applyToAllDisplays(wallpaper) }
                        }
                        Button("Chỉnh sửa…") { edit(wallpaper) }
                        Divider()
                        Button("Xoá…", role: .destructive) { delete(wallpaper) }
                    }
                }
            }
            .padding(3)
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(
                offset: geometry.contentOffset.x,
                scroll: ShelfScroll(contentWidth: geometry.contentSize.width, visibleWidth: geometry.containerSize.width)
            )
        } action: { _, new in
            metrics = new
        }
        .mask { EdgeFade(leading: edges.hasEarlier, trailing: edges.hasLater) }
        .overlay(alignment: .topLeading) {
            if edges.hasEarlier { PageButton(forward: false) { page(forward: false) } }
        }
        .overlay(alignment: .topTrailing) {
            if edges.hasLater { PageButton(forward: true) { page(forward: true) } }
        }
        .animation(.smooth(duration: 0.2), value: [edges.hasEarlier, edges.hasLater])
        .onHover { hovering in
            if hovering { wheel.start(scrollSideways) } else { wheel.stop() }
        }
        .onDisappear { wheel.stop() }
        .padding(-3)
    }

    private func page(forward: Bool) {
        withAnimation(.smooth(duration: 0.35)) {
            position.scrollTo(x: metrics.scroll.page(from: metrics.offset, forward: forward))
        }
    }

    private func scrollSideways(deltaX: Double, deltaY: Double, isPrecise: Bool) -> Bool {
        guard let target = metrics.scroll.wheel(from: metrics.offset, deltaX: deltaX, deltaY: deltaY, isPrecise: isPrecise) else {
            return false
        }
        position.scrollTo(x: target)
        return true
    }
}

/// Fades whichever end still has videos beyond it.
private struct EdgeFade: View {
    let leading: Bool
    let trailing: Bool

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: leading ? 56 : 0)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: trailing ? 56 : 0)
        }
    }
}

private struct PageButton: View {
    let forward: Bool
    let action: () -> Void

    var body: some View {
        let title = forward ? "Xem các video tiếp theo" : "Xem các video trước"
        Button(action: action) {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.black.opacity(0.35)).interactive(), in: .circle)
        .accessibilityLabel(title)
        .help(title)
            .frame(height: 90)
            .padding(.top, 3)
            .padding(.horizontal, 8)
            .transition(.opacity)
    }
}

/// A mouse wheel only turns vertically, so over the shelf its events are taken before the
/// scroll view sees them and applied sideways.
@MainActor
private final class WheelRedirect {
    private var monitor: Any?

    func start(_ scroll: @escaping @MainActor (_ deltaX: Double, _ deltaY: Double, _ isPrecise: Bool) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let deltaX = Double(event.scrollingDeltaX)
            let deltaY = Double(event.scrollingDeltaY)
            let isPrecise = event.hasPreciseScrollingDeltas
            let handled = MainActor.assumeIsolated { scroll(deltaX, deltaY, isPrecise) }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ShelfItem: View {
    let wallpaper: Wallpaper
    let isApplied: Bool
    @Binding var hovered: Wallpaper?
    let action: () -> Void

    @ViewState private var isHovering = false
    private let shape = RoundedRectangle(cornerRadius: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: action) {
                Color.clear
                    .overlay { CoverImage(wallpaper: wallpaper).scaledToFill() }
                    .frame(width: 144, height: 90)
                    .clipShape(shape)
                    .overlay {
                        shape.inset(by: -3)
                            .strokeBorder(.white, lineWidth: 2)
                            .opacity(isApplied ? 1 : 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if wallpaper.playsAudio {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .shadow(radius: 3)
                                .padding(8)
                        }
                    }
                    .offset(y: isHovering ? -2 : 0)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(wallpaper.name)
            .accessibilityValue(isApplied ? "Đang dùng làm hình nền" : "")

            Text(wallpaper.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 144, alignment: .leading)
        }
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.18), value: isHovering)
        .task(id: isHovering) {
            guard isHovering else {
                if hovered?.id == wallpaper.id { hovered = nil }
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { hovered = wallpaper }
        }
    }
}

struct CoverImage: View {
    let wallpaper: Wallpaper
    @ViewState private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: "\(wallpaper.id)-\(wallpaper.coverTime)") {
            let url = AppModel.coverURL(of: wallpaper)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            image = data.flatMap(NSImage.init(data:))
        }
    }
}

/// A silent loop of a library video.
struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(url: url)
    }

    func updateNSView(_ view: PreviewView, context: Context) {}

    static func dismantleNSView(_ view: PreviewView, coordinator: ()) {
        view.stop()
    }

    @MainActor
    final class PreviewView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var loading: Task<Void, Never>?

        init(url: URL) {
            super.init(frame: .zero)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
            wantsLayer = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            loading = Task {
                let asset = await VideoAsset.make(url: url, withAudio: false)
                guard !Task.isCancelled else { return }
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
                player.play()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func stop() {
            loading?.cancel()
            player.pause()
            looper?.disableLooping()
            player.removeAllItems()
        }
    }
}
