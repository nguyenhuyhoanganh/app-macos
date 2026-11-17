import LuminaCore
import SwiftUI

/// Một công cụ trong mục "Công cụ". Thêm công cụ mới = thêm một `ToolItem` vào `ToolsSection.tools`
/// (và, nếu có phần sổ ra, một nhánh trong `detail(for:)` / `detailHeight(for:)`).
/// - `.toggle`: bật/tắt (vd Ngăn ngủ).
/// - `.disclosure`: bấm để sổ phần riêng ngay dưới hàng của nó (vd bản đồ Sắp xếp, bảng Xoay).
/// Công cụ đang có hiệu lực (`active`) và có `quickOff` thì hiện một icon phát sáng ở hàng tiêu đề
/// của mục — bên ngoài danh sách — bấm icon đó là tắt, không cần mở mục ra.
struct ToolItem: Identifiable {
    enum Kind {
        case toggle(Binding<Bool>)
        case disclosure
    }

    let id: String
    let title: String
    let symbol: String
    /// Biểu tượng khi đang có hiệu lực, nếu khác `symbol`.
    var activeSymbol: String?
    let status: String
    let help: String
    let kind: Kind
    var active = false
    var quickOff: (() -> Void)?
    var quickOffLabel = ""

    var currentSymbol: String { active ? activeSymbol ?? symbol : symbol }
    var showsBadge: Bool { active && quickOff != nil }
}

/// Mục "Công cụ": một thẻ như thẻ màn hình. Bấm hàng tiêu đề để sổ ra danh sách công cụ
/// (accordion chung với danh sách chế độ của các màn: mở cái này thì cái kia đóng).
struct ToolsSection: View {
    @Environment(AppState.self) private var app
    @Environment(PanelLayout.self) private var layout

    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 4
    static let listTopPadding: CGFloat = 10
    static let detailPadding: CGFloat = 8
    static let mapHeight: CGFloat = 150
    static let rotateRowHeight: CGFloat = 30
    static let rotateRowSpacing: CGFloat = 4
    static let mainRowHeight: CGFloat = 28
    static let mainRowSpacing: CGFloat = 8

    private var rotatable: [DisplaySnapshot] { app.displays.filter(\.canRotate) }

    private var tools: [ToolItem] {
        var list = [
            ToolItem(id: "sleep", title: "Ngăn ngủ", symbol: "cup.and.heat.waves",
                     activeSymbol: "cup.and.heat.waves.fill",
                     status: app.preventSleep ? "Đang giữ màn hình thức" : "Tắt",
                     help: "Giữ màn hình và máy không tự ngủ khi để yên",
                     kind: .toggle(Binding(get: { app.preventSleep },
                                           set: { on in withAnimation(.smooth(duration: 0.25)) { app.preventSleep = on } })),
                     active: app.preventSleep,
                     quickOff: { withAnimation(.smooth(duration: 0.25)) { app.preventSleep = false } },
                     quickOffLabel: "Tắt Ngăn ngủ"),
            ToolItem(id: "arrange", title: "Sắp xếp màn hình",
                     symbol: "arrow.up.and.down.and.arrow.left.and.right",
                     status: "\(app.displays.count) màn hình · màn chính: "
                         + (app.displays.first(where: \.isMain).map(Self.shortName) ?? "—"),
                     help: "Kéo-thả để đổi vị trí các màn hình, chọn màn chính",
                     kind: .disclosure),
        ]
        if app.canSyncBrightness, let source = app.syncSource {
            var nits = app.nits(for: source).map { "≈ \(Int($0.rounded())) nit" } ?? ""
            // Màn phụ không theo kịp (sáng/tối hơn mức nó làm được): ghi rõ, màn chuẩn vẫn kéo tiếp được.
            if app.brightnessSync, let capped = app.displays.first(where: { app.syncLimit(for: $0) != .none }) {
                let p = app.profile(for: capped)
                nits += app.syncLimit(for: capped) == .atMax
                    ? " · \(Self.shortName(capped)) kịch \(Int(p.maxNits))"
                    : " · \(Self.shortName(capped)) tối nhất \(Int(p.minNits))"
            }
            list.insert(ToolItem(
                id: "sync", title: "Đồng bộ độ sáng", symbol: "sun.max", activeSymbol: "sun.max.fill",
                status: app.brightnessSync ? "Theo \(Self.shortName(source)) · \(nits)" : "Tắt · mỗi màn chỉnh riêng",
                help: "Các màn khác sáng bằng \(Self.shortName(source)) (theo nit ước lượng). Kéo thanh của màn khác để bù cho khớp mắt.",
                kind: .toggle(Binding(get: { app.brightnessSync },
                                      set: { on in withAnimation(.smooth(duration: 0.25)) { app.brightnessSync = on } })),
                active: app.brightnessSync,
                quickOff: { withAnimation(.smooth(duration: 0.25)) { app.brightnessSync = false } },
                quickOffLabel: "Tắt đồng bộ độ sáng"), at: 1)
        }
        if app.canMirror {
            let main = app.displays.first(where: \.isMain).map(Self.shortName) ?? "màn chính"
            list.append(ToolItem(
                id: "mirror", title: "Phản chiếu màn hình", symbol: "rectangle.on.rectangle",
                activeSymbol: "rectangle.fill.on.rectangle.fill",
                status: app.isMirroring ? "Mọi màn đang hiện giống \(main)" : "Tắt · mỗi màn một desktop (mở rộng)",
                help: "Bật: mọi màn hiện giống màn chính (phản chiếu). Tắt: mở rộng, mỗi màn một desktop",
                kind: .toggle(Binding(get: { app.isMirroring }, set: { app.setMirroring($0) })),
                active: app.isMirroring,
                quickOff: { app.setMirroring(false) },
                quickOffLabel: "Tắt phản chiếu"))
        }
        let rotatable = rotatable
        if MonitorPanel.canRotateAtAll, !rotatable.isEmpty {
            let rotated = rotatable.filter { $0.rotation != 0 }
            list.append(ToolItem(
                id: "rotate", title: "Xoay màn hình", symbol: "rotate.right", activeSymbol: "rotate.right.fill",
                status: rotated.isEmpty ? "Không xoay"
                                        : rotated.map { "\(Self.shortName($0)) \($0.rotation)°" }.joined(separator: ", "),
                help: "Xoay màn hình 90°, 180°, 270°",
                kind: .disclosure,
                active: !rotated.isEmpty,
                quickOff: { app.resetRotation() },
                quickOffLabel: "Bỏ xoay màn hình"))
        }
        return list
    }

    static func shortName(_ d: DisplaySnapshot) -> String { d.isBuiltIn ? "Tích hợp" : d.name }

    var body: some View {
        let all = tools
        let open = layout.toolsOpen
        let natural = listHeight(all)
        // Màn thấp (vd màn tích hợp) không đủ chỗ: danh sách co lại và cuộn bên trong.
        let height = DevTools.isSnapshot ? natural : min(natural, max(layout.toolsBudget, Self.rowHeight * 3))
        VStack(spacing: 0) {
            // + lề platter (2 × 10) và lề trên (8)
            header(all).measure { layout.toolsChromeHeight = $0 + 28 }
            // Danh sách luôn nằm trong cây view; chỉ chiều cao được animate (giống danh sách chế độ).
            Group {
                if natural > height + 0.5 {
                    ScrollView { list(all) }.scrollIndicators(.automatic)
                } else {
                    list(all)
                }
            }
                .frame(height: open ? height : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
        .platter(padding: 10)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func listHeight(_ all: [ToolItem]) -> CGFloat {
        let n = all.count
        let rows = CGFloat(n) * Self.rowHeight + CGFloat(max(n - 1, 0)) * Self.rowSpacing
        let detail = layout.openTool.map { detailHeight(for: $0) } ?? 0
        return Self.listTopPadding + rows + detail
    }

    /// Chiều cao phần sổ ra của một công cụ, gồm khoảng hở phía trên.
    private func detailHeight(for id: String) -> CGFloat {
        switch id {
        case "arrange":
            let mainRow = app.displays.count > 1 ? Self.mainRowSpacing + Self.mainRowHeight : 0
            return Self.rowSpacing + Self.mapHeight + mainRow + 2 * Self.detailPadding
        case "rotate":
            let n = CGFloat(rotatable.count)
            return Self.rowSpacing + 2 * Self.detailPadding + n * Self.rotateRowHeight
                + max(n - 1, 0) * Self.rotateRowSpacing
        default:
            return 0
        }
    }

    // MARK: Tiêu đề

    private func header(_ all: [ToolItem]) -> some View {
        let active = all.filter(\.showsBadge)
        let toggleOpen = { withAnimation(PopoverView.expand) { layout.toolsOpen.toggle() } }
        return HStack(spacing: 8) {
            Button(action: toggleOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.chip))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Công cụ").font(.system(size: 13, weight: .semibold))
                        Text(active.isEmpty ? "\(all.count) công cụ"
                                            : active.map(\.title).joined(separator: ", ") + " đang bật")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Công cụ")
            .accessibilityValue(layout.toolsOpen ? "đang mở" : "đang đóng")

            // Icon phát sáng của công cụ đang bật: nằm ngoài danh sách, bấm là tắt.
            ForEach(active) { QuickOffBadge(item: $0) }

            Button(action: toggleOpen) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(layout.toolsOpen ? 180 : 0))
                    .frame(width: 22, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .animation(.smooth(duration: 0.25), value: active.map(\.id))
    }

    // MARK: Danh sách

    private func list(_ all: [ToolItem]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(all) { item in
                VStack(spacing: 0) {
                    ToolRow(item: item, isOpen: layout.openTool == item.id) {
                        switch item.kind {
                        case .toggle(let value): value.wrappedValue.toggle()
                        case .disclosure:
                            withAnimation(PopoverView.expand) {
                                layout.openTool = layout.openTool == item.id ? nil : item.id
                            }
                        }
                    }
                    detailBlock(for: item.id)
                }
            }
        }
        .padding(.top, Self.listTopPadding)
    }

    /// Phần sổ ra luôn nằm trong cây view; chỉ chiều cao được animate.
    @ViewBuilder private func detailBlock(for id: String) -> some View {
        let height = detailHeight(for: id)
        if height > 0 {
            let open = layout.openTool == id
            detail(for: id)
                .padding(Self.detailPadding)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.platter)
                }
                .padding(.top, Self.rowSpacing)
                .frame(height: open ? height : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
    }

    @ViewBuilder private func detail(for id: String) -> some View {
        switch id {
        case "arrange": ArrangePanel()
        case "rotate": RotatePanel(displays: rotatable)
        default: EmptyView()
        }
    }
}

/// Một hàng công cụ: vòng tròn biểu tượng + tên + trạng thái; bên phải là công tắc (bật/tắt)
/// hoặc mũi tên (sổ ra). Bấm cả hàng là bật/tắt hoặc sổ ra.
private struct ToolRow: View {
    let item: ToolItem
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        let on = item.active || isOpen
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.currentSymbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(on ? AnyShapeStyle(Theme.accentBlue) : AnyShapeStyle(Theme.chip)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(item.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 8)
            .frame(height: ToolsSection.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.platter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.help)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.status)
        .accessibilityAddTraits(isToggle ? .isToggle : [])
        .animation(.smooth(duration: 0.2), value: on)
    }

    private var isToggle: Bool {
        if case .toggle = item.kind { return true }
        return false
    }

    @ViewBuilder private var trailing: some View {
        switch item.kind {
        case .toggle(let value):
            MiniSwitch(isOn: value.wrappedValue)
        case .disclosure:
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .frame(width: 22)
        }
    }
}

/// Công tắc mini chỉ để hiển thị (cả hàng là nút bấm), cùng kiểu công tắc "Mở cùng máy".
private struct MiniSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(Theme.accentBlue) : AnyShapeStyle(Color.primary.opacity(0.16)))
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(1.5)
            }
            .accessibilityHidden(true)
    }
}

/// Icon phát sáng của một công cụ đang bật, đặt ở tiêu đề mục Công cụ. Bấm là tắt công cụ;
/// rê chuột vào thì hiện dấu × để báo trước.
private struct QuickOffBadge: View {
    let item: ToolItem
    @ViewState private var hovering = false

    var body: some View {
        Button {
            item.quickOff?()
        } label: {
            ZStack {
                Circle().fill(Theme.accentBlue)
                Image(systemName: hovering ? "xmark" : item.currentSymbol)
                    .font(.system(size: hovering ? 10 : 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 26, height: 26)
            // Quầng sáng hai lớp: lõi đậm sát viền + toả rộng mờ.
            .shadow(color: Theme.accentBlue.opacity(0.85), radius: 4)
            .shadow(color: Theme.accentBlue.opacity(0.45), radius: 11)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(item.title) đang bật — bấm để tắt")
        .accessibilityLabel(item.quickOffLabel)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

/// Bảng Sắp xếp: bản đồ kéo-thả + chọn màn chính (màn có menu bar và Dock).
private struct ArrangePanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let displays = app.displays
        VStack(spacing: ToolsSection.mainRowSpacing) {
            DisplayMapView()
            if displays.count > 1 {
                HStack(spacing: 8) {
                    Text("Màn chính").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    SegmentedChips(options: displays.map(ToolsSection.shortName),
                                   selected: displays.firstIndex(where: \.isMain),
                                   accessibilityLabel: { "Màn chính \(ToolsSection.shortName(displays[$0]))" }) {
                        app.makeMain(displays[$0])
                    }
                }
                .frame(height: ToolsSection.mainRowHeight)
            }
        }
    }
}

/// Bảng Xoay: mỗi màn một hàng, chọn 0° / 90° / 180° / 270°. Xoay xong chờ xác nhận như đổi độ phân giải.
private struct RotatePanel: View {
    @Environment(AppState.self) private var app
    let displays: [DisplaySnapshot]

    static let angles = [0, 90, 180, 270]

    var body: some View {
        VStack(spacing: ToolsSection.rotateRowSpacing) {
            ForEach(displays) { d in
                HStack(spacing: 8) {
                    Image(systemName: d.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
                    Text(ToolsSection.shortName(d)).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 4)
                    SegmentedChips(options: Self.angles.map { "\($0)°" },
                                   selected: Self.angles.firstIndex(of: d.rotation),
                                   itemWidth: 40,
                                   accessibilityLabel: { "Xoay \(ToolsSection.shortName(d)) \(Self.angles[$0]) độ" }) {
                        app.rotate(d, to: Self.angles[$0])
                    }
                }
                .frame(height: ToolsSection.rotateRowHeight)
            }
        }
    }
}

/// Bản đồ thu nhỏ bố cục màn hình. Kéo một màn rồi thả: tự hít vào cạnh màn bên cạnh và áp dụng.
struct DisplayMapView: View {
    @Environment(AppState.self) private var app

    @ViewState private var dragging: CGDirectDisplayID?
    @ViewState private var translation: CGSize = .zero

    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let displays = app.displays
            let map = MapTransform(displays.map(\.bounds), in: geo.size, inset: Self.inset)
            ZStack(alignment: .topLeading) {
                Color.clear   // khung nền do platter bên ngoài vẽ — không lồng thêm một lớp

                // Vị trí sẽ hít vào khi thả (khung nét đứt)
                if let id = dragging, let d = displays.first(where: { $0.id == id }) {
                    let snapped = snappedRect(for: d, displays: displays, scale: map.scale)
                    let r = map.rect(snapped)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.accentBlue, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }

                ForEach(displays) { d in
                    let r = map.rect(d.bounds)
                    let isDragging = dragging == d.id
                    DisplayTile(display: d, highlighted: isDragging)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX + (isDragging ? translation.width : 0),
                                y: r.minY + (isDragging ? translation.height : 0))
                        .zIndex(isDragging ? 1 : 0)
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                dragging = d.id
                                translation = g.translation
                            }
                            .onEnded { g in
                                let proposed = CGPoint(x: d.bounds.minX + g.translation.width / map.scale,
                                                       y: d.bounds.minY + g.translation.height / map.scale)
                                app.moveDisplay(d.id, to: proposed)
                                withAnimation(.smooth(duration: 0.25)) {
                                    dragging = nil
                                    translation = .zero
                                }
                            })
                        .accessibilityElement()
                        .accessibilityLabel("\(d.name), \(Int(d.bounds.width))×\(Int(d.bounds.height))\(d.isMain ? ", màn chính" : "")")
                        .accessibilityHint("Kéo để đổi vị trí màn hình")
                }
            }
            .animation(.smooth(duration: 0.3), value: displays.map(\.bounds))
        }
        .frame(height: ToolsSection.mapHeight)
    }

    private func snappedRect(for d: DisplaySnapshot, displays: [DisplaySnapshot], scale: CGFloat) -> CGRect {
        let proposed = CGRect(x: d.bounds.minX + translation.width / scale,
                              y: d.bounds.minY + translation.height / scale,
                              width: d.bounds.width, height: d.bounds.height)
        let origin = ArrangementPlanner.snap(proposed, others: displays.filter { $0.id != d.id }.map(\.bounds))
        return CGRect(origin: origin, size: d.bounds.size)
    }
}

/// Đổi toạ độ toàn cục (pt) sang toạ độ bản đồ: thu nhỏ cả bố cục cho vừa khung, căn giữa.
struct MapTransform {
    let scale: CGFloat
    let origin: CGPoint
    let offset: CGPoint

    init(_ rects: [CGRect], in size: CGSize, inset: CGFloat) {
        let union = rects.reduce(CGRect.null) { $0.union($1) }
        let u = union.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : union
        // Chừa chỗ để kéo một màn ra mép mà vẫn nằm trong khung.
        let s = min((size.width - 2 * inset) / u.width, (size.height - 2 * inset) / u.height)
        scale = s
        origin = u.origin
        offset = CGPoint(x: (size.width - u.width * s) / 2, y: (size.height - u.height * s) / 2)
    }

    func rect(_ r: CGRect) -> CGRect {
        CGRect(x: offset.x + (r.minX - origin.x) * scale, y: offset.y + (r.minY - origin.y) * scale,
               width: r.width * scale, height: r.height * scale)
    }
}

/// Một màn trên bản đồ. Màn chính có vạch menu bar phía trên.
private struct DisplayTile: View {
    let display: DisplaySnapshot
    let highlighted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(highlighted ? Theme.accentBlue.opacity(0.35) : Color.primary.opacity(0.16))
            shape.strokeBorder(highlighted ? Theme.accentBlue : Color.primary.opacity(0.22), lineWidth: 1)
            if display.isMain {
                Capsule().fill(Color.primary.opacity(0.55)).frame(height: 3).padding(.horizontal, 6).padding(.top, 4)
            }
            Text(display.isBuiltIn ? "Tích hợp" : display.name)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(shape)
    }
}
