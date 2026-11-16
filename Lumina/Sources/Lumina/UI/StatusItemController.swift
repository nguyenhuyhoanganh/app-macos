import AppKit
import LuminaCore
import Observation
import SwiftUI

/// Trạng thái bố cục của popover, dùng chung cho mọi thẻ màn hình.
@MainActor @Observable
final class PanelLayout {
    /// Chiều cao tối đa: từ ngay dưới icon tới đáy vùng dùng được của màn.
    var maxHeight: CGFloat = .greatestFiniteMagnitude
    /// Accordion: chỉ một phần được mở tại một thời điểm — danh sách chế độ của một màn,
    /// hoặc bản đồ sắp xếp màn hình.
    var expandedDisplay: CGDirectDisplayID? {
        didSet { if expandedDisplay != nil { arrangeOpen = false } }
    }
    var arrangeOpen = false {
        didSet { if arrangeOpen { expandedDisplay = nil } }
    }
    /// Chiều cao phần không phải danh sách (đo từ layout, không phụ thuộc animation).
    var chromeHeight: CGFloat = 0
    var cardBaseHeights: [CGDirectDisplayID: CGFloat] = [:]
    /// Gọi khi tấm kính đổi chiều cao đích (dùng cho công cụ chẩn đoán).
    @ObservationIgnored var onContentResize: ((CGFloat) -> Void)?

    /// Chỗ còn lại cho danh sách chế độ để cả popover vừa màn mà không cần cuộn giao diện chính.
    var listBudget: CGFloat {
        let used = chromeHeight + cardBaseHeights.values.reduce(0, +)
        return max(96, maxHeight - used - 8)
    }
}

/// Icon menu bar + popover tự quản lý (thay cho SwiftUI MenuBarExtra).
///
/// - Vị trí: MenuBarExtra chỉ đặt cửa sổ một lần lúc mở; khi đổi độ phân giải toạ độ toàn cục của
///   mọi màn bị dịch nên popover văng khỏi icon. Ở đây panel được neo lại dưới icon mỗi khi màn
///   đổi cấu hình hoặc icon di chuyển.
/// - Animation: panel có kích thước cố định, trong suốt; tấm kính là của SwiftUI nên co giãn cùng
///   một animation với nội dung. Không đổi khung cửa sổ trong lúc animation (nguồn gây giật trước đây).
@MainActor
final class StatusItemController: NSObject {
    /// Lề trong suốt quanh tấm kính (trái, phải, trên) để quầng bóng của kính mờ hết trước mép cửa sổ.
    /// 16 pt là quá hẹp: bóng bị mép cửa sổ cắt thành hình chữ nhật góc vuông.
    static let shadowInset: CGFloat = 40

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: PopoverPanel
    private let hosting: NSHostingView<AnyView>
    let layout = PanelLayout()
    /// Màn chứa icon mà người dùng đã bấm. macOS vẽ một bản icon trên menu bar của mỗi màn
    /// (bản trên màn tích hợp có thể bị tai thỏ che) và có thể tạo lại các bản này khi đổi cấu hình.
    private var anchorDisplay: CGDirectDisplayID?
    private var outsideClickMonitor: Any?
    private var repositionWork: DispatchWorkItem?

    init(app: AppState) {
        let inset = Self.shadowInset
        let root = PopoverView()
            .environment(app)
            .environment(layout)
            .padding(.horizontal, inset)
            .padding(.top, inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []          // cửa sổ không chạy theo kích thước nội dung
        panel = PopoverPanel(contentRect: NSRect(x: 0, y: 0, width: Theme.popoverWidth + 2 * inset, height: 400),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Không dùng bóng cửa sổ: với cửa sổ trong suốt, macOS dựng bóng theo quầng mờ của lớp kính
        // tràn ra phần lề và vẽ thêm một viền đen bao quanh cách tấm kính ~16 pt. Kính tự có viền và bóng riêng.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.onCancel = { [weak self] in self?.close() }

        if let button = statusItem.button {
            button.image = MenuBarIcon.image
            button.target = self
            button.action = #selector(togglePanel(_:))
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(anchorMoved(_:)), name: NSWindow.didMoveNotification, object: nil)
        nc.addObserver(self, selector: #selector(panelResignedKey), name: NSWindow.didResignKeyNotification, object: panel)
    }

    var isShown: Bool { panel.isVisible }

    // MARK: Mở / đóng

    @objc private func togglePanel(_ sender: Any?) {
        if panel.isVisible { close() } else { open(from: NSApp.currentEvent?.window) }
    }

    func open(from window: NSWindow? = nil) {
        anchorDisplay = (window ?? statusItem.button?.window)?.screen?.displayID
        reposition()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    @objc private func panelResignedKey() {
        // Bấm vào app khác thì đóng, như popover hệ thống. Thanh đếm ngược vẫn chạy trong AppState.
        close()
    }

    // MARK: Neo vị trí

    @objc private func screensChanged() {
        // Mỗi lần đổi mode có 2 sự kiện liên tiếp và icon có lúc nằm ở toạ độ rác: đặt ngay một lần,
        // rồi đặt lại sau khi hệ thống ổn định.
        reposition()
        scheduleReposition(after: 0.35)
    }

    @objc private func anchorMoved(_ note: Notification) {
        guard panel.isVisible, let w = note.object as? NSWindow,
              String(describing: type(of: w)).contains("StatusBarWindow") else { return }
        reposition()
    }

    private func scheduleReposition(after delay: TimeInterval) {
        repositionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reposition() }
        repositionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Icon dùng làm mốc: bản icon hiện nằm trên màn đã bấm; màn đó mất thì bản icon trên màn có con trỏ.
    private func currentAnchor() -> NSWindow? {
        let icons = NSApp.windows.filter {
            String(describing: type(of: $0)).contains("StatusBarWindow")
                && PopoverPlacement.isUsableAnchor($0.frame, screenFrame: $0.screen?.frame)
        }
        if let id = anchorDisplay, let w = icons.first(where: { $0.screen?.displayID == id }) { return w }
        let mouse = NSEvent.mouseLocation
        return icons.first(where: { $0.screen?.frame.contains(mouse) == true }) ?? icons.first
    }

    /// Panel = khung cố định từ ngay dưới icon tới đáy màn; nội dung neo ở mép trên.
    func reposition() {
        guard let anchor = currentAnchor(), let screen = anchor.screen else {
            // Icon đang ở toạ độ tạm trong lúc đổi mode: thử lại, không đặt panel theo toạ độ rác.
            if panel.isVisible { scheduleReposition(after: 0.25) }
            return
        }
        let visible = screen.visibleFrame
        let limit = PopoverPlacement.maxHeight(anchor: anchor.frame, visibleFrame: visible)
        if layout.maxHeight != limit { layout.maxHeight = limit }

        // Đặt tấm kính như trước (ngay dưới icon, trong màn), rồi nới cửa sổ ra hai bên và lên trên.
        let glass = PopoverPlacement.frame(anchor: anchor.frame, visibleFrame: visible,
                                           size: CGSize(width: Theme.popoverWidth, height: limit))
        let i = Self.shadowInset
        let frame = NSRect(x: glass.minX - i, y: glass.minY, width: glass.width + 2 * i, height: glass.height + i)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Chẩn đoán: chiều cao đang hiển thị của layer rộng bằng tấm kính (giá trị presentation).
    func renderedGlassHeight() -> CGFloat? {
        func walk(_ l: CALayer, _ depth: Int) -> CGFloat? {
            var best: CGFloat?
            let b = (l.presentation() ?? l).bounds
            if abs(b.width - Theme.popoverWidth) < 1 { best = b.height }
            if depth < 8 {
                for s in l.sublayers ?? [] {
                    if let h = walk(s, depth + 1) { best = max(best ?? 0, h) }
                }
            }
            return best
        }
        return hosting.layer.flatMap { walk($0, 0) }
    }

    // Cho công cụ chẩn đoán.
    var anchorFrame: NSRect? { currentAnchor()?.frame }
    var panelFrame: NSRect { panel.frame }
    /// Khung tấm kính (cửa sổ trừ lề trong suốt).
    var glassFrame: NSRect {
        let f = panel.frame, i = Self.shadowInset
        return NSRect(x: f.minX + i, y: f.minY, width: f.width - 2 * i, height: f.height - i)
    }
    var panelContentView: NSView? { panel.contentView }
    var panelScreenFrame: NSRect? { currentAnchor()?.screen?.visibleFrame }
    func openOnExternalForTesting() {
        let icon = NSApp.windows.first {
            String(describing: type(of: $0)).contains("StatusBarWindow") && $0.screen?.displayID.map { CGDisplayIsBuiltin($0) == 0 } == true
        }
        open(from: icon)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Panel không viền vẫn nhận bàn phím (Esc, Return cho nút "Giữ").
final class PopoverPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Phần lề trong suốt được phép chờm lên menu bar; không để AppKit đẩy cửa sổ xuống.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - Tấm kính

extension View {
    /// Nền Liquid Glass cho popover. macOS 26+: `glassEffect` (kính thật, khúc xạ những gì sau cửa sổ);
    /// macOS 14–25: vật liệu popover thế hệ trước. Gate theo phiên bản, không dùng helper `.if`.
    @ViewBuilder
    func popoverGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background { BehindWindowMaterial().clipShape(shape) }
        }
    }
}

private struct BehindWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
