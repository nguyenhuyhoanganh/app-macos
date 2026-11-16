import AppKit
import AVFoundation
import LivewallCore
import SwiftUI

/// Name, tags and the frame used as the cover and the still desktop picture.
struct EditSheet: View {
    @ViewState private var name: String
    @ViewState private var tags: String
    @ViewState private var time: Double
    @ViewState private var loopMode: LoopMode
    @Environment(\.dismiss) private var dismiss

    private let wallpaper: Wallpaper
    private let save: (Wallpaper, LoopMode) -> Void
    private let delete: () -> Void

    init(wallpaper: Wallpaper, save: @escaping (Wallpaper, LoopMode) -> Void, delete: @escaping () -> Void) {
        self.wallpaper = wallpaper
        self.save = save
        self.delete = delete
        _name = ViewState(initialValue: wallpaper.name)
        _tags = ViewState(initialValue: wallpaper.tags.joined(separator: " "))
        _time = ViewState(initialValue: wallpaper.coverTime)
        _loopMode = ViewState(initialValue: wallpaper.loopMode)
    }

    var body: some View {
        VStack(spacing: 16) {
            FramePicker(url: Paths.videos.appendingPathComponent(wallpaper.fileName), time: time)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text("Ảnh bìa và ảnh nền tĩnh")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Slider(value: $time, in: 0...max(wallpaper.duration, 0.1))
            }
            HStack(spacing: 12) {
                TextField("Tên", text: $name)
                TextField("Thẻ, cách nhau bằng dấu cách", text: $tags)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Kiểu lặp", selection: $loopMode) {
                    ForEach(LoopMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(loopMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Xoá video", role: .destructive) {
                    dismiss()
                    delete()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Huỷ", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Lưu") {
                    var updated = wallpaper
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.name = trimmed.isEmpty ? wallpaper.name : trimmed
                    updated.tags = Tags.parse(tags)
                    updated.coverTime = time
                    save(updated, loopMode)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 480)
    }
}

private struct FramePicker: NSViewRepresentable {
    let url: URL
    let time: Double

    func makeNSView(context: Context) -> FrameView {
        FrameView(url: url)
    }

    func updateNSView(_ view: FrameView, context: Context) {
        view.seek(to: time)
    }

    final class FrameView: NSView {
        private let player: AVPlayer

        init(url: URL) {
            player = AVPlayer(url: url)
            super.init(frame: .zero)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
            wantsLayer = true
            player.isMuted = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func seek(to seconds: Double) {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
}
