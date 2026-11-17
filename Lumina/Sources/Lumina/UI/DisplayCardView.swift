import LuminaCore
import SwiftUI

/// Khối một màn hình: tên, độ sáng, độ phân giải, danh sách chế độ.
/// Dùng control gốc (Slider, Toggle) để tự nhận kiểu Liquid Glass của macOS 26/27.
struct DisplayCardView: View {
    @Environment(AppState.self) private var app
    @Environment(PanelLayout.self) private var layout
    let display: DisplaySnapshot

    @ViewState private var brightness: Double = 0
    @ViewState private var editingBrightness = false
    @ViewState private var step: Double = 0
    @ViewState private var editingResolution = false
    @ViewState private var showAll = false
    @ViewState private var toggleRowHeight: CGFloat = 22

    private var listOpen: Bool { layout.expandedDisplay == display.id }

    private var sliderModes: [Resolution] { ModeCatalog.sliderModes(display.modes, current: display.current) }
    private var brightnessState: BrightnessState? { app.brightness[display.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let state = brightnessState { brightnessSection(state) }
                resolutionSection
                modeListToggle
            }
            .measure { layout.cardBaseHeights[display.id] = $0 + 2 * 12 }   // + padding của platter
            // Danh sách luôn nằm trong cây view; chỉ chiều cao được animate → giãn ra mượt.
            modeList
                .frame(height: listOpen ? listHeight : 0, alignment: .top)
                .clipped()
                .opacity(listOpen ? 1 : 0)
                .allowsHitTesting(listOpen)
                .accessibilityHidden(!listOpen)
        }
        .platter()
        .onAppear {
            syncFromDisplay()
            if DevTools.expandLists, !display.isBuiltIn, layout.expandedDisplay == nil { layout.expandedDisplay = display.id }
        }
        .onDisappear {
            layout.cardBaseHeights[display.id] = nil
            if layout.expandedDisplay == display.id { layout.expandedDisplay = nil }
        }
        .onChange(of: display) { syncFromDisplay() }
        .onChange(of: brightnessState) {
            if !editingBrightness, let s = brightnessState { brightness = s.value }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.chip))
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if display.hasHDR {
                // Như công tắc "Dải động cao" trong Cài đặt hệ thống › Màn hình.
                Toggle("HDR", isOn: Binding(get: { display.hdrOn }, set: { app.setHDR(display, on: $0) }))
                    .glassSwitch(fill: false)
                    .help("Dải động cao (HDR) — như trong Cài đặt hệ thống › Màn hình")
                    .accessibilityLabel("HDR \(display.name)")
            }
            if brightnessState?.kind == .hardware { Chip(text: "DDC", prominent: true) }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !display.isBuiltIn, let code = display.identity.vendorCode { parts.append(code) }
        if let d = display.diagonal {
            parts.append(String(format: "%.1f″", d).replacingOccurrences(of: ".0″", with: "″").replacingOccurrences(of: ".", with: ","))
        }
        parts.append(display.isBuiltIn ? "tích hợp" : "màn ngoài")
        if display.isMain { parts.append("màn chính") }
        return parts.joined(separator: " · ")
    }

    // MARK: Độ sáng

    private func brightnessSection(_ state: BrightnessState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ControlHeader(title: "Độ sáng") {
                switch state.kind {
                case .system: Chip(text: "Hệ thống")
                case .hardware: Chip(text: "Phần cứng", prominent: true)
                case .software: Chip(text: "Phần mềm")
                }
                if app.brightnessSync, let nits = app.nits(for: display) {
                    let limit = app.syncLimit(for: display)
                    Text("≈ \(Int(nits.rounded())) nit" + (limit == .atMax ? " · kịch max" : limit == .atMin ? " · tối nhất" : ""))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .help(display.id == app.syncSource?.id ? "Màn chuẩn của Đồng bộ độ sáng"
                                                               : "Đang đồng bộ theo \(app.syncSource.map(ToolsSection.shortName) ?? "màn chuẩn")")
                }
                Text("\(Int((brightness * 100).rounded()))%")
                    .monospacedDigit().frame(width: 36, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.min").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: $brightness, in: 0...1) {
                    Text("Độ sáng \(display.name)")
                } onEditingChanged: { editing in
                    editingBrightness = editing
                    if !editing { app.setBrightness(brightness, for: display) }
                }
                .labelsHidden()
                .onChange(of: brightness) {
                    if editingBrightness { app.setBrightness(brightness, for: display) }
                }
                Image(systemName: "sun.max.fill").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Độ phân giải

    private var resolutionSection: some View {
        let modes = sliderModes
        let shown = modes.isEmpty ? display.current.resolution : modes[index(of: step, in: modes)]
        return VStack(alignment: .leading, spacing: 4) {
            ControlHeader(title: "Độ phân giải") {
                Text(shown.label).monospacedDigit()
                Text(detail(for: shown)).foregroundStyle(.secondary)
                hidpiSwitch.padding(.leading, 4)
            }
            if modes.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size.larger").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityLabel("Chữ to hơn")
                    Slider(value: $step, in: 0...Double(modes.count - 1), step: 1) {
                        Text("Độ phân giải \(display.name)")
                    } onEditingChanged: { editing in
                        editingResolution = editing
                        if !editing { app.select(modes[index(of: step, in: modes)], on: display) }
                    }
                    .labelsHidden()
                    Image(systemName: "rectangle.expand.diagonal").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityLabel("Nhiều chỗ hơn")
                }
            }
            aspectRow
        }
    }

    /// Tỉ lệ khung hình có trên màn (16:9, 16:10, 21:9…). Chọn tỉ lệ khác → đổi sang độ phân giải
    /// của tỉ lệ đó có chiều cao gần nhất; thanh trượt sau đó đi theo tỉ lệ mới.
    @ViewBuilder private var aspectRow: some View {
        let groups = ModeCatalog.aspectGroups(display.modes)
        if groups.count > 1 {
            HStack(spacing: 8) {
                Text("Tỉ lệ").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                SegmentedChips(options: groups.map(\.label),
                               selected: groups.firstIndex { $0.contains(display.current.resolution) },
                               accessibilityLabel: { "Tỉ lệ \(groups[$0].label) \(display.name)" }) { i in
                    if let r = ModeCatalog.resolution(for: groups[i], modes: display.modes, current: display.current) {
                        app.select(r, on: display)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func index(of value: Double, in modes: [Resolution]) -> Int {
        min(max(Int(value.rounded()), 0), modes.count - 1)
    }

    private func detail(for r: Resolution) -> String {
        r == display.current.resolution ? "· \(Int(display.current.refreshRate.rounded())) Hz" : ""
    }

    /// Công tắc HiDPI: đổi giữa chế độ HiDPI và thường, giữ kích thước nếu có (xem
    /// `ModeCatalog.hidpiCounterpart`). Đi qua `app.select` nên cũng tự hoàn tác sau 15 giây.
    private var hidpiSwitch: some View {
        let isOn = display.current.resolution.isHiDPI
        let target = ModeCatalog.hidpiCounterpart(display.modes, current: display.current, hidpi: !isOn)
        return Toggle("HiDPI", isOn: Binding(
            get: { isOn },
            set: { _ in if let target { app.select(target, on: display) } }))
            .glassSwitch(fill: false)
            .disabled(target == nil)
            .help(target.map { isOn ? "Tắt HiDPI: chuyển sang \($0.label) thường"
                                    : "Bật HiDPI: chuyển sang \($0.label) HiDPI (nét hơn)" }
                  ?? (isOn ? "Màn này không có chế độ thường" : "Màn này không có chế độ HiDPI"))
            .accessibilityLabel("HiDPI \(display.name)")
    }

    private func syncFromDisplay() {
        if !editingResolution, let i = sliderModes.firstIndex(of: display.current.resolution) {
            step = Double(i)
        }
        if !editingBrightness, let s = brightnessState { brightness = s.value }
    }

    // MARK: Danh sách chế độ

    private var listModes: [Resolution] {
        ModeCatalog.listModes(display.modes, current: display.current, showAll: showAll)
    }

    private var modeListToggle: some View {
        Button {
            // Accordion: mở màn này thì danh sách của màn kia đóng lại (cùng một animation).
            withAnimation(PopoverView.expand) {
                layout.expandedDisplay = listOpen ? nil : display.id
            }
        } label: {
            HStack {
                Image(systemName: "list.bullet")
                Text("Tất cả chế độ")
                Text("\(listModes.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(listOpen ? 180 : 0))
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Theme.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(listOpen ? "đang mở" : "đang đóng")
    }

    // Kích thước danh sách
    private static let rowHeight: CGFloat = 32
    private static let rowSpacing: CGFloat = 1
    private static let listTopPadding: CGFloat = 8
    private static let toggleSpacing: CGFloat = 6
    /// Vùng hàng cao tối đa ~7 dòng; nhiều hơn thì cuộn trong danh sách (giao diện phụ).
    private static let maxRowsHeight: CGFloat = 232

    private var rowsNaturalHeight: CGFloat {
        let n = CGFloat(listModes.count)
        return max(0, n * Self.rowHeight + (n - 1) * Self.rowSpacing)
    }

    /// Vùng hàng: cao bằng nội dung, nhưng không vượt chỗ còn lại trên màn (khi đó mới cuộn).
    private var rowsHeight: CGFloat {
        let fixed = Self.listTopPadding + Self.toggleSpacing + toggleRowHeight
        let budget = DevTools.isSnapshot ? .greatestFiniteMagnitude : layout.listBudget - fixed
        return min(rowsNaturalHeight, Self.maxRowsHeight, max(Self.rowHeight * 3, budget))
    }

    private var listHeight: CGFloat {
        Self.listTopPadding + rowsHeight + Self.toggleSpacing + toggleRowHeight
    }

    private var modeList: some View {
        VStack(alignment: .leading, spacing: Self.toggleSpacing) {
            OptionalScroll {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(listModes.enumerated()), id: \.offset) { _, r in
                        modeRow(r)
                    }
                }
            }
            .frame(height: rowsHeight)
            .scrollIndicators(rowsHeight < rowsNaturalHeight ? .automatic : .never)
            Toggle("Hiện mọi chế độ (cả không HiDPI, mọi tỉ lệ)", isOn: $showAll.animation(PopoverView.expand))
                .glassSwitch()
                .padding(.horizontal, 8)
                .measure { toggleRowHeight = $0 }
        }
        .padding(.top, Self.listTopPadding)
    }

    private func modeRow(_ r: Resolution) -> some View {
        let on = r == display.current.resolution
        let rate = ModeCatalog.refreshRates(for: r, in: display.modes).first
        return Button { app.select(r, on: display) } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                Text(r.label).monospacedDigit().font(.system(size: 13, weight: on ? .semibold : .regular))
                Spacer()
                if r.isHiDPI { Chip(text: "HiDPI") }
                if let rate { Chip(text: "\(Int(rate.rounded())) Hz") }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(on ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(Color.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
