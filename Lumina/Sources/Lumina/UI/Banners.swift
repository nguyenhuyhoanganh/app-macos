import SwiftUI

/// Thanh đếm ngược "Giữ thay đổi?" — dùng chung cho popover và cửa sổ (cùng một `AppState.pending`).
struct PendingBanner: View {
    @Environment(AppState.self) private var app
    let change: PendingChange

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.tint.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: change.timer.fraction(at: app.now))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(change.timer.remaining(at: app.now))")
                    .font(.system(size: 12, weight: .bold)).monospacedDigit()
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Giữ \(change.summary)?").font(.system(size: 12.5, weight: .semibold))
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
    }
}

/// Thông báo lỗi có nút đóng — dùng chung cho popover và cửa sổ.
struct ErrorBanner: View {
    @Environment(AppState.self) private var app
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button { app.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Đóng thông báo")
        }
        .platter(padding: 10)
    }
}
