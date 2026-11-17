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

/// Nhóm lựa chọn nhỏ kiểu segmented (góc xoay, tỉ lệ, màn chính): nền xám, mục đang chọn tô xanh.
struct SegmentedChips: View {
    let options: [String]
    let selected: Int?
    /// Rộng cố định mỗi mục (vd 40 cho "270°"); `nil` = theo chữ.
    var itemWidth: CGFloat?
    var accessibilityLabel: (Int) -> String = { _ in "" }
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selected
                Button { pick(i) } label: {
                    Text(options[i])
                        .font(.system(size: 11, weight: on ? .semibold : .regular))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, itemWidth == nil ? 8 : 0)
                        .frame(width: itemWidth, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on ? AnyShapeStyle(Theme.accentBlue) : AnyShapeStyle(Color.clear))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(i).isEmpty ? options[i] : accessibilityLabel(i))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))
        .animation(.smooth(duration: 0.2), value: selected)
    }
}
