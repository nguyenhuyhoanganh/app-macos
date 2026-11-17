import SwiftUI

/// Nội dung popover trên tấm kính. Không có thanh cuộn ở giao diện chính:
/// chỉ danh sách chế độ (giao diện phụ) được cuộn, và nó tự co để cả popover vừa màn.
struct PopoverView: View {
    @Environment(AppState.self) private var app
    @Environment(PanelLayout.self) private var layout

    static let expand = Animation.smooth(duration: 0.32)

    var body: some View {
        VStack(spacing: 0) {
            header.measure { chrome.header = $0 }
            VStack(spacing: 8) {
                ForEach(app.displays) { d in
                    DisplayCardView(display: d)
                }
            }
            .padding(.horizontal, 10)
            // Mục Công cụ tự báo phần cố định của nó (layout.toolsChromeHeight); danh sách bên trong
            // không được đo vào đây, để ngân sách chiều cao không phụ thuộc vào chính nó.
            ToolsSection()
            VStack(spacing: 0) {
                if let p = app.pending {
                    PendingBanner(change: p)
                        .padding(.horizontal, 10).padding(.top, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
                if let error = app.errorMessage {
                    ErrorBanner(message: error).padding(.horizontal, 10).padding(.top, 8).transition(.opacity)
                }
                footer
            }
            .measure { chrome.bottom = $0 }
        }
        .frame(width: Theme.popoverWidth)
        .popoverGlass(cornerRadius: Theme.cornerRadius)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { layout.onContentResize?($0) }
        .animation(Self.expand, value: app.pending != nil)
        .animation(Self.expand, value: app.errorMessage)
        .onAppear { app.registry.reload(); app.refreshBrightness(); app.refreshLoginItem() }
        .onChange(of: chrome) {
            // padding giữa các thẻ: 8 pt mỗi khe
            let gaps = CGFloat(max(app.displays.count - 1, 0)) * 8
            layout.chromeHeight = chrome.header + chrome.bottom + gaps
        }
    }

    @ViewState private var chrome = ChromeHeights()

    struct ChromeHeights: Equatable {
        var header: CGFloat = 0
        var bottom: CGFloat = 0
    }

    private var header: some View {
        HStack {
            Text("Lumina").font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("\(app.displays.count) màn hình").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Mở cùng máy", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                .glassSwitch(fill: false)
            Spacer()
            Button {
                AppDelegate.statusItem?.close()
                MainWindowController.shared.show()
            } label: {
                Image(systemName: "macwindow").font(.system(size: 13))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Mở cửa sổ Lumina")
            .accessibilityLabel("Mở cửa sổ Lumina")
            .keyboardShortcut(",")
            Button("Thoát Lumina") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 16) }
        .padding(.top, 8)
    }
}

extension View {
    /// Báo chiều cao layout của view (giá trị đích, không phải giá trị đang animation).
    func measure(_ action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { action($0) }
    }
}
