import LuminaCore
import SwiftUI

/// Mục "Công cụ": ngăn ngủ + sắp xếp màn hình (bản đồ thu nhỏ, kéo-thả).
struct ToolsSection: View {
    @Environment(AppState.self) private var app
    @Environment(PanelLayout.self) private var layout

    static let mapHeight: CGFloat = 150

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $app.preventSleep) {
                    Label("Ngăn ngủ", systemImage: app.preventSleep ? "cup.and.heat.waves.fill" : "moon.zzz")
                }
                .glassSwitch()
                .help("Giữ màn hình và máy không tự ngủ khi để yên")

                Button {
                    withAnimation(PopoverView.expand) { layout.arrangeOpen.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        Text("Sắp xếp màn hình")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(layout.arrangeOpen ? 180 : 0))
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.chip))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityValue(layout.arrangeOpen ? "đang mở" : "đang đóng")
            }

            // Bản đồ luôn nằm trong cây view; chỉ chiều cao được animate (giống danh sách chế độ).
            DisplayMapView()
                .padding(.top, 10)
                .frame(height: layout.arrangeOpen ? Self.mapHeight + 10 : 0, alignment: .top)
                .clipped()
                .opacity(layout.arrangeOpen ? 1 : 0)
                .allowsHitTesting(layout.arrangeOpen)
                .accessibilityHidden(!layout.arrangeOpen)
        }
        .platter()
        .padding(.horizontal, 10)
        .padding(.top, 8)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04))

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
