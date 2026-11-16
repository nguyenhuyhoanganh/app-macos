import SwiftUI

/// Khối nền bo góc đặt trên tấm kính, kiểu module của Control Center.
struct Platter: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: Theme.platterRadius, style: .continuous).fill(Theme.platter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.platterRadius, style: .continuous)
                    .strokeBorder(Theme.platterStroke, lineWidth: 0.5)
            }
    }
}

extension View {
    func platter(padding: CGFloat = 12) -> some View { modifier(Platter(padding: padding)) }
}

/// Nhãn nhỏ (DDC, Phần cứng, HiDPI…).
struct Chip: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(prominent ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Theme.chip))
            }
    }
}

/// Hàng tiêu đề nhỏ cho một điều khiển: nhãn bên trái, giá trị bên phải.
struct ControlHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            trailing
        }
        .font(.system(size: 12))
    }
}

/// Công tắc nhỏ kiểu Control Center: nhãn trái, switch mini phải; bật thì xanh cùng tông icon app.
/// Thay cho checkbox xanh trông thô.
struct GlassSwitchStyle: ToggleStyle {
    /// true: switch dạt về mép phải dòng; false: switch nằm ngay cạnh nhãn.
    var fill = true

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if fill { Spacer(minLength: 4) }
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accentBlue)         // bật: xanh cùng tông icon app
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

extension View {
    func glassSwitch(fill: Bool = true) -> some View { toggleStyle(GlassSwitchStyle(fill: fill)) }
}
