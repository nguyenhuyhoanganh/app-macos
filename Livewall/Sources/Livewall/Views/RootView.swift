import AppKit
import LivewallCore
import SwiftUI
import UniformTypeIdentifiers

/// The window is the wallpaper: video fills it, glass floats only along the edges.
struct RootView: View {
    @Bindable var model: AppModel
    @ViewState private var hovered: Wallpaper?
    @ViewState private var isDropTargeted = false
    @ViewState private var showsSettings = false
    @ViewState private var showsFilter = false
    @ViewState private var editing: Wallpaper?
    @ViewState private var deleting: Wallpaper?

    private var applied: Wallpaper? { model.currentDisplay.flatMap { model.wallpaper(on: $0.key) } }
    private var onStage: Wallpaper? { hovered ?? applied ?? model.library.items.first }

    var body: some View {
        ZStack {
            if model.library.items.isEmpty {
                EmptyStage(importing: model.importing > 0, choose: chooseVideos)
            } else {
                StageBackdrop(wallpaper: onStage, isLive: model.isWindowVisible)
                StageChrome(
                    model: model,
                    onStage: onStage,
                    isPreviewing: hovered != nil && hovered?.id != applied?.id,
                    hovered: $hovered,
                    add: chooseVideos,
                    edit: { editing = $0 },
                    delete: { deleting = $0 }
                )
                topBar
            }
            if isDropTargeted { DropHint() }
        }
        .overlay(alignment: .top) { noticeView }
        .animation(.smooth(duration: 0.3), value: model.notice)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .sheet(item: $editing) { wallpaper in
            EditSheet(wallpaper: wallpaper, save: { model.update($0, loopMode: $1) }, delete: { deleting = wallpaper })
        }
        .confirmationDialog(
            "Xoá video này?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { wallpaper in
            Button("Xoá", role: .destructive) { model.delete(wallpaper) }
        } message: { wallpaper in
            Text(model.isShowing(wallpaper)
                ? "Video này đang được dùng làm hình nền. Hình nền cũ sẽ được khôi phục."
                : "Video sẽ bị xoá khỏi thư viện. Tệp gốc của bạn vẫn còn.")
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Spacer()
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        SearchField(text: $model.filter.text)
                        filterButton
                        Button("Cài đặt", systemImage: "gearshape") { showsSettings.toggle() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                            .popover(isPresented: $showsSettings, arrowEdge: .bottom) {
                                SettingsPanel(model: model)
                            }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
            Spacer()
        }
    }

    private var filterButton: some View {
        Button("Lọc", systemImage: model.filter.isActive
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease") { showsFilter.toggle() }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .popover(isPresented: $showsFilter, arrowEdge: .bottom) {
                FilterPanel(filter: $model.filter)
            }
    }

    @ViewBuilder
    private var noticeView: some View {
        if let progress = model.renderProgress {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(width: 120)
                Text("Đang tạo vòng lặp \(Int(progress * 100))%")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 60)
        } else if let notice = model.notice {
            Text(notice)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func chooseVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Thêm"
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

extension VideoShape {
    var title: String {
        switch self {
        case .standard: "Tiêu chuẩn"
        case .wide: "Rộng 21:9"
        case .ultrawide: "Siêu rộng 32:9"
        case .portrait: "Dọc"
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tìm video", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button("Xoá tìm kiếm", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 220, height: 38)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Nothing to show yet, so a slow colour field gives the glass something to bend.
private struct EmptyStage: View {
    let importing: Bool
    let choose: () -> Void

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                MeshGradient(width: 3, height: 3, points: points(at: context.date), colors: Self.colors)
            }
            VStack(spacing: 22) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 50, weight: .light))
                VStack(spacing: 8) {
                    Text("Kéo video vào đây")
                        .font(.system(size: 26, weight: .bold))
                    Text("Video sẽ trở thành hình nền sống trên desktop của bạn.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                }
                if importing {
                    ProgressView().controlSize(.regular)
                } else {
                    Button("Chọn video", action: choose)
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .controlSize(.extraLarge)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .frame(width: 420)
            .glassEffect(.regular, in: .rect(cornerRadius: 34))
        }
    }

    private static let colors: [Color] = [
        .init(red: 0.05, green: 0.04, blue: 0.14), .init(red: 0.42, green: 0.26, blue: 0.84), .init(red: 0.05, green: 0.04, blue: 0.14),
        .init(red: 0.08, green: 0.59, blue: 0.59), .init(red: 0.15, green: 0.47, blue: 0.84), .init(red: 0.42, green: 0.26, blue: 0.84),
        .init(red: 0.05, green: 0.04, blue: 0.14), .init(red: 0.94, green: 0.44, blue: 0.38), .init(red: 0.05, green: 0.04, blue: 0.14),
    ]

    private func points(at date: Date) -> [SIMD2<Float>] {
        let time = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)) * 0.25
        let drift = SIMD2<Float>(0.5 + 0.14 * sin(time), 0.5 + 0.14 * cos(time * 0.8))
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], drift, [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }
}

private struct DropHint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 26)
            .strokeBorder(.white, style: StrokeStyle(lineWidth: 2.5, dash: [10, 8]))
            .padding(12)
            .allowsHitTesting(false)
    }
}
