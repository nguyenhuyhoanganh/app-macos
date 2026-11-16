import AppKit
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel
    let openWindow: () -> Void
    let quit: () -> Void

    var body: some View {
        Button("Mở Livewall", action: openWindow)
        Divider()
        if model.displays.count == 1, let display = model.displays.first {
            DisplayMenu(model: model, display: display)
        } else {
            ForEach(model.displays) { display in
                Menu(display.name) {
                    DisplayMenu(model: model, display: display)
                }
            }
        }
        Divider()
        Button("Thoát Livewall", action: quit)
    }
}

private struct DisplayMenu: View {
    let model: AppModel
    let display: DisplayInfo

    private let levels = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        let config = model.state.config(for: display.key)
        Text(model.status(of: display.key))
        if config.wallpaperID != nil {
            Toggle("Bật hình nền", isOn: Binding(
                get: { config.isEnabled },
                set: { model.setEnabled($0, for: display.key) }
            ))
            if model.wallpaper(on: display.key)?.playsAudio == true {
                Picker("Âm lượng", selection: Binding(
                    get: { levels.min { abs($0 - config.volume) < abs($1 - config.volume) } ?? 0 },
                    set: { model.setVolume($0, for: display.key) }
                )) {
                    ForEach(levels, id: \.self) { level in
                        Text(level == 0 ? "Tắt tiếng" : "\(Int(level * 100))%").tag(level)
                    }
                }
            }
            Button("Gỡ hình nền") { model.removeWallpaper(from: display.key) }
        }
    }
}
