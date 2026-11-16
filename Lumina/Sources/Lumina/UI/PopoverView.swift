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
            VStack(spacing: 0) {
                ToolsSection()
                if let p = app.pending {
                    revertBar(p).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
                if let error = app.errorMessage {
                    errorBar(error).transition(.opacity)
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
        .onAppear { app.registry.reload(); app.refreshBrightness(); launchAtLogin = LoginItem.isEnabled }
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

    private func revertBar(_ p: PendingChange) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.tint.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: p.timer.fraction(at: app.now))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(p.timer.remaining(at: app.now))")
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Giữ \(p.summary)?").font(.system(size: 12.5, weight: .semibold))
                Text("Tự hoàn tác nếu không xác nhận").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Hoàn tác") { app.revertPending() }
                .buttonStyle(.bordered)
            Button("Giữ") { app.keepPending() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .platter(padding: 10)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func errorBar(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button { app.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Đóng thông báo")
        }
        .platter(padding: 10)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewState private var launchAtLogin = LoginItem.isEnabled

    private var footer: some View {
        HStack {
            // Gọi đăng ký/huỷ ngay trong binding. Không dùng .onChange rồi đọc lại trạng thái:
            // SMAppService cập nhật trạng thái hơi trễ, đọc lại ngay sẽ thấy "chưa bật", gán ngược vào
            // công tắc làm .onChange chạy lần nữa và huỷ đăng ký (lỗi đã gặp).
            Toggle("Mở cùng máy", isOn: Binding(
                get: { launchAtLogin },
                set: { wanted in
                    do {
                        try LoginItem.set(wanted)
                        launchAtLogin = wanted
                    } catch {
                        app.errorMessage = "Không đổi được “Mở cùng máy”: \(error.localizedDescription)"
                        launchAtLogin = LoginItem.isEnabled
                    }
                }))
                .glassSwitch(fill: false)
            Spacer()
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
