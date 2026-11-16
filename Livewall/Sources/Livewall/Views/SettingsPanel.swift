import LivewallCore
import SwiftUI

struct SettingsPanel: View {
    let model: AppModel

    private var energy: EnergySettings { model.state.energy }

    private var pausesWhenCovered: Binding<Bool> {
        Binding(get: { energy.pauseWhenCovered }, set: {
            var updated = energy
            updated.pauseWhenCovered = $0
            model.setEnergy(updated)
        })
    }

    private var batteryRule: Binding<BatteryRule> {
        Binding(get: { energy.batteryRule }, set: {
            var updated = energy
            updated.batteryRule = $0
            model.setEnergy(updated)
        })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Tạm dừng khi desktop bị che", isOn: pausesWhenCovered)
                Picker("Khi dùng pin", selection: batteryRule) {
                    Text("Vẫn phát").tag(BatteryRule.off)
                    ForEach([80, 50, 20, 5], id: \.self) { level in
                        Text("Dừng dưới \(level)%").tag(BatteryRule.below(level))
                    }
                    Text("Luôn dừng").tag(BatteryRule.always)
                }
            }
            Section {
                Toggle("Khởi động cùng máy", isOn: Binding(
                    get: { model.startsAtLogin },
                    set: { model.setStartsAtLogin($0) }
                ))
                Toggle("Ẩn icon trên desktop", isOn: Binding(
                    get: { model.state.hidesDesktopIcons },
                    set: { model.setHidesDesktopIcons($0) }
                ))
                Toggle("Ẩn biểu tượng trên menu bar", isOn: Binding(
                    get: { model.state.hidesMenuBarIcon },
                    set: { model.setHidesMenuBarIcon($0) }
                ))
            } footer: {
                if model.state.hidesMenuBarIcon {
                    Text("Mở lại Livewall từ thư mục Applications để hiện cửa sổ này.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Thư viện", value: model.usage?.totalText ?? "…")
                if let rendered = model.usage?.renderedText {
                    LabeledContent("Trong đó dựng cho Qua lại", value: rendered)
                }
                Button("Dọn file thừa") { Task { await model.cleanUp() } }
                    .disabled(model.importing > 0 || model.renderProgress != nil)
            } footer: {
                Text("File thừa cũng được tự dọn mỗi lần mở app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await model.refreshUsage() }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct FilterPanel: View {
    @Binding var filter: WallpaperFilter

    var body: some View {
        Form {
            Toggle("Chỉ video có âm thanh", isOn: $filter.soundOnly)
            Picker("Tỉ lệ", selection: $filter.shape) {
                Text("Mọi tỉ lệ").tag(VideoShape?.none)
                ForEach(VideoShape.allCases, id: \.self) { shape in
                    Text(shape.title).tag(VideoShape?.some(shape))
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
}
