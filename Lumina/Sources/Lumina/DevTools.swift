import AppKit
import LuminaCore
import SwiftUI

/// Công cụ kiểm thử giao diện không cần quyền Screen Recording hay bấm chuột.
@MainActor
enum DevTools {
    static var expandLists: Bool { CommandLine.arguments.contains("--expand") }

    /// Render popover (dữ liệu thật) ra PNG @2x.
    static func snapshot(to path: String, after seconds: Double, then done: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            let view = PopoverView().environment(Shared.app).environment(PanelLayout()).frame(width: Theme.popoverWidth)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("snapshot \(path)")
            } else {
                print("snapshot FAILED")
            }
            done()
        }
    }

    static func selfTestRevert(displayArg: String, spec: String, snapshot path: String?) {
        let app = Shared.app
        let parts = spec.lowercased().split(separator: "x").compactMap { Int($0) }
        guard let id = UInt32(displayArg), let d = app.registry.display(id), parts.count == 2 else {
            print("selftest FAIL: bad args"); exit(2)
        }
        let original = d.current
        let target = Resolution(width: parts[0], height: parts[1], isHiDPI: original.isHiDPI)
        print("selftest: \(d.name) \(original.resolution.label) → \(target.label)")
        app.select(target, on: d)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            app.registry.reload()
            let during = app.registry.display(id)?.current.resolution.label ?? "?"
            print("t+2s: mode=\(during) pending=\(app.pending?.summary ?? "nil") remaining=\(app.pending?.timer.remaining(at: Date()) ?? -1)s")
            if let path { snapshot(to: path, after: 0) {} }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) {
            app.registry.reload()
            let after = app.registry.display(id)?.current
            let ok = after?.id == original.id && app.pending == nil
            print("t+18s: mode=\(after?.resolution.label ?? "?") pending=\(app.pending == nil ? "nil" : "still") → \(ok ? "PASS tự hoàn tác" : "FAIL")")
            exit(ok ? 0 : 1)
        }
    }
}

extension DevTools {
    static var isSnapshot: Bool { CommandLine.arguments.contains("--snapshot") }
}

/// ScrollView bình thường; khi render ảnh (ImageRenderer không vẽ ScrollView) thì xếp phẳng.
struct OptionalScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if DevTools.isSnapshot { content } else { ScrollView { content } }
    }
}

extension DevTools {
    /// Chẩn đoán: mở popover dưới icon trên màn ngoài, rồi mỗi 0,5 giây kiểm tra popover còn neo đúng
    /// (mép trên ngay dưới icon, nằm trọn trong vùng dùng được của màn) hay không.
    static func tracePopover(seconds: Double) {
        guard let controller = AppDelegate.statusItem else { print("no status item"); exit(2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.openOnExternalForTesting() }
        let start = Date()
        var bad = 0, samples = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
            MainActor.assumeIsolated {
                let el = Date().timeIntervalSince(start)
                guard el > 1.5 else { return }
                let p = controller.glassFrame
                var status = "no-anchor"
                if let a = controller.anchorFrame, let vis = controller.panelScreenFrame {
                    let topOK = abs(p.maxY - (a.minY - PopoverPlacement.gap)) < 1
                    let inside = vis.insetBy(dx: -1, dy: -1).contains(p)
                    let centered = abs(p.midX - a.midX) < 1 || p.minX <= vis.minX + 9 || p.maxX >= vis.maxX - 9
                    status = (topOK && inside && centered && controller.isShown) ? "OK" : "BAD(top=\(topOK) inside=\(inside) centered=\(centered) shown=\(controller.isShown))"
                    samples += 1
                    if status != "OK" { bad += 1 }
                    print(String(format: "%5.1f ", el) + "icon=\(NSStringFromRect(a)) panel=\(NSStringFromRect(p)) \(status)")
                } else {
                    print(String(format: "%5.1f ", el) + "icon=? (đang đổi cấu hình) panel=\(NSStringFromRect(p))")
                }
                fflush(stdout)
                if el > seconds {
                    t.invalidate()
                    print("RESULT samples=\(samples) bad=\(bad)")
                    exit(bad == 0 && samples > 0 ? 0 : 1)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            print(String(format: "%5.1f ---- didChangeScreenParameters", Date().timeIntervalSince(start))); fflush(stdout)
        }
    }
}

extension DevTools {
    /// Mở panel thật dưới icon (màn ngoài) rồi chụp view hierarchy của nó ra PNG.
    /// Nền kính do WindowServer ghép nên không có trong ảnh; dùng để soát bố cục và control.
    static func panelSnapshot(to path: String) {
        guard let controller = AppDelegate.statusItem else { exit(2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            controller.openOnExternalForTesting()
            let args = CommandLine.arguments
            if args.contains("--tools") || args.contains("--arrange") { controller.layout.toolsOpen = true }
            if args.contains("--arrange") { controller.layout.arrangeOpen = true }
            if args.contains("--rotate") { controller.layout.toolsOpen = true; controller.layout.openTool = "rotate" }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let view = controller.panelContentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("FAILED"); exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("panel \(NSStringFromRect(controller.panelFrame)) content=\(type(of: view)) appearance=\(view.effectiveAppearance.name.rawValue) → \(path)")
            exit(0)
        }
    }
}

extension DevTools {
    /// Đo animation giãn/thu của danh sách chế độ: ghi chiều cao tấm kính theo từng khung hình.
    /// Mượt = nhiều giá trị trung gian, đơn điệu, kéo dài ≈ thời lượng animation; giật = nhảy 1–2 bước.
    static func expandTest() {
        guard let c = AppDelegate.statusItem else { exit(2) }
        let layout = c.layout
        var samples: [(t: CFTimeInterval, h: CGFloat)] = []
        let shadowRefresh = layout.onContentResize
        layout.onContentResize = { h in samples.append((CACurrentMediaTime(), h)); shadowRefresh?(h) }

        func step(_ name: String, after: Double, _ change: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                samples.removeAll()
                let t0 = CACurrentMediaTime()
                // Lấy mẫu lớp render: chiều cao layer rộng bằng tấm kính, 120 lần/giây.
                var rendered: [CGFloat] = []
                let sampler = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        if let h = c.renderedGlassHeight() { rendered.append(h) }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    sampler.invalidate()
                    var distinct: [CGFloat] = []
                    for h in rendered where distinct.last.map({ abs($0 - h) > 0.5 }) ?? true { distinct.append(h) }
                    let jumps = zip(distinct, distinct.dropFirst()).map { abs($1 - $0) }
                    let total = abs((distinct.last ?? 0) - (distinct.first ?? 0))
                    print(String(format: "   lớp render: %d giá trị khác nhau, %.0f → %.0f pt, bước lớn nhất %.0f pt (%.0f%% quãng đường)",
                                 distinct.count, distinct.first ?? 0, distinct.last ?? 0, jumps.max() ?? 0,
                                 total > 0 ? (jumps.max() ?? 0) / total * 100 : 0))
                    print("   " + distinct.map { String(format: "%.0f", $0) }.joined(separator: " "))
                    fflush(stdout)
                }
                withAnimation(PopoverView.expand) { change() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let hs = samples.map(\.h)
                    let span = (samples.last?.t ?? t0) - (samples.first?.t ?? t0)
                    let monotonic = zip(hs, hs.dropFirst()).allSatisfy { $0 <= $1 } || zip(hs, hs.dropFirst()).allSatisfy { $0 >= $1 }
                    let maxJump = zip(hs, hs.dropFirst()).map { abs($1 - $0) }.max() ?? 0
                    let total = abs((hs.last ?? 0) - (hs.first ?? 0))
                    print(String(format: "%@: %d khung, %.0f ms, %.0f → %.0f pt, bước lớn nhất %.0f pt (%.0f%%), đơn điệu=%@, mở=%@",
                                 name, hs.count, span * 1000, hs.first ?? 0, hs.last ?? 0, maxJump,
                                 total > 0 ? maxJump / total * 100 : 0, monotonic ? "có" : "không",
                                 layout.expandedDisplay.map(String.init) ?? "không"))
                    fflush(stdout)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { c.openOnExternalForTesting() }
        let ext = Shared.app.displays.first { !$0.isBuiltIn }?.id
        let mac = Shared.app.displays.first { $0.isBuiltIn }?.id
        step("Mở danh sách Kuycon", after: 2.0) { layout.expandedDisplay = ext }
        step("Chuyển sang màn tích hợp (accordion)", after: 3.2) { layout.expandedDisplay = mac }
        step("Đóng", after: 4.4) { layout.expandedDisplay = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) { exit(0) }
    }
}

extension DevTools {
    /// Vẽ icon menu bar phóng to 8× trên nền sáng và nền tối, cạnh cỡ thật 1× và 2×.
    static func menuBarPreview(to path: String) {
        let scale: CGFloat = 8, w: CGFloat = 18 * scale
        let size = NSSize(width: w * 2 + 120, height: w)
        let img = NSImage(size: size, flipped: true) { _ in
            for (i, (bg, fg)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.16, alpha: 1), NSColor.white)].enumerated() {
                let x = CGFloat(i) * (w + 120)
                bg.setFill(); NSRect(x: x, y: 0, width: w + 120, height: w).fill()
                for (j, s) in [scale, 1, 2].enumerated() {
                    let ox = j == 0 ? x : x + w + 10 + CGFloat(j - 1) * 40
                    let oy: CGFloat = j == 0 ? 0 : 20
                    NSGraphicsContext.saveGraphicsState()
                    let t = NSAffineTransform(); t.translateX(by: ox, yBy: oy); t.scale(by: s); t.concat()
                    fg.set()
                    MenuBarIcon.drawTinted(fg)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            return true
        }
        if let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("menubar preview → \(path)")
        }
    }
}

extension MenuBarIcon {
    static func drawTinted(_ color: NSColor) {
        // draw() dùng màu đen; vẽ vào lớp rồi tô màu để xem trên nền tối.
        NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        color.setFill()
        NSRect(x: 0, y: 0, width: 18, height: 18).fill(using: .sourceAtop)
        NSGraphicsContext.current?.cgContext.endTransparencyLayer()
    }
}

extension DevTools {
    /// Bật/tắt "Ngăn ngủ" qua AppState rồi đọc `pmset -g assertions` để xác nhận với hệ thống.
    static func sleepTest() {
        func assertions() -> String {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g", "assertions"]
            p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return out.split(separator: "\n").filter { $0.contains("Lumina") }.joined(separator: "\n")
        }
        let app = Shared.app
        let before = app.preventSleep
        app.preventSleep = true
        let on = assertions()
        print("bật: " + (on.isEmpty ? "KHÔNG thấy assertion" : on.trimmingCharacters(in: .whitespaces)))
        app.preventSleep = false
        let off = assertions()
        print("tắt: " + (off.isEmpty ? "assertion đã gỡ" : "VẪN còn: \(off)"))
        app.preventSleep = before
        exit(!on.isEmpty && off.isEmpty ? 0 : 1)
    }
}

extension DevTools {
    /// Bấm thật vào mục Công cụ (gửi sự kiện chuột vào panel, qua hit-testing của SwiftUI):
    /// mở mục → tắt Ngăn ngủ bằng icon phát sáng → bật lại ở hàng trong danh sách → sổ bản đồ → đóng mục.
    /// Trả Ngăn ngủ về trạng thái ban đầu trước khi thoát.
    static func toolsClickTest() {
        guard let c = AppDelegate.statusItem else { exit(2) }
        let app = Shared.app, layout = c.layout
        let before = app.preventSleep
        var failures = 0

        // Phần tử trợ năng của SwiftUI là lớp riêng: gọi động qua giao thức NSAccessibility.
        func elements(_ root: AnyObject) -> [AnyObject] {
            let kids = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
            return kids + kids.flatMap(elements)
        }
        func find(_ label: String) -> AnyObject? {
            guard let view = c.panelContentView else { return nil }
            return elements(view).first {
                ($0.accessibilityLabel?() ?? nil) == label && !($0.isAccessibilityHidden?() ?? false)
            }
        }
        func click(_ label: String) -> Bool {
            guard let el = find(label), let window = c.panelContentView?.window else {
                print("✗ không thấy “\(label)”"); failures += 1; return false
            }
            guard let f = el.accessibilityFrame?() else { print("✗ “\(label)” không có khung"); failures += 1; return false }
            let p = window.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 1, pressure: 1) {
                    window.sendEvent(e)
                }
            }
            return true
        }
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "✓ " : "✗ ") + name)
            if !ok { failures += 1 }
        }

        app.preventSleep = true
        var steps: [(Double, () -> Void)] = [
            (1.0, { c.openOnExternalForTesting() }),
            (2.0, { check("mục đóng lúc đầu, icon phát sáng hiện", !layout.toolsOpen && find("Tắt Ngăn ngủ") != nil)
                    _ = click("Công cụ") }),
            (2.8, { check("bấm tiêu đề → mục mở", layout.toolsOpen)
                    _ = click("Tắt Ngăn ngủ") }),
            (3.5, { check("bấm icon phát sáng → Ngăn ngủ tắt", !app.preventSleep)
                    check("icon phát sáng biến mất", find("Tắt Ngăn ngủ") == nil)
                    check("mục vẫn mở", layout.toolsOpen)
                    _ = click("Ngăn ngủ") }),
            (4.2, { check("bấm hàng Ngăn ngủ → bật lại", app.preventSleep)
                    check("icon phát sáng hiện lại", find("Tắt Ngăn ngủ") != nil)
                    _ = click("Sắp xếp màn hình") }),
            (5.0, { check("bấm hàng Sắp xếp → bản đồ sổ ra", layout.arrangeOpen)
                    layout.expandedDisplay = CGMainDisplayID() }),
            (5.6, { check("mở danh sách chế độ → mục Công cụ tự đóng (accordion)", !layout.toolsOpen)
                    layout.expandedDisplay = nil
                    _ = click("Tắt Ngăn ngủ") }),
            (6.3, { check("icon phát sáng tắt được cả khi mục đang đóng", !app.preventSleep && !layout.toolsOpen)
                    app.preventSleep = before
                    withAnimation(PopoverView.expand) { layout.toolsOpen = true } }),
        ]
        // Xoay + HiDPI trên màn ngoài (có thật trên máy, đổi xong trả lại).
        let ext = { app.displays.first { !$0.isBuiltIn } }
        let extName = ext().map(ToolsSection.shortName) ?? "?"
        var end = 7.0
        if let e = ext(), e.canRotate, MonitorPanel.canRotateAtAll {
            let originalRotation = e.rotation
            steps += [
                (7.0, { _ = click("Xoay màn hình") }),
                (7.8, { check("bấm hàng Xoay → bảng xoay sổ ra", layout.openTool == "rotate")
                        _ = click("Xoay \(extName) 90 độ") }),
                (11.0, { check("chọn 90° → màn xoay 90°", ext()?.rotation == 90)
                         check("xoay chờ xác nhận (tự hoàn tác 15 giây)", app.pending.map { $0.revert == .rotation(originalRotation) } ?? false)
                         check("icon phát sáng của Xoay hiện", find("Bỏ xoay màn hình") != nil)
                         _ = click("Bỏ xoay màn hình") }),
                (14.0, { check("bấm icon phát sáng → màn về 0°", ext()?.rotation == 0)
                         check("không còn chờ xác nhận", app.pending == nil)
                         check("icon phát sáng của Xoay biến mất", find("Bỏ xoay màn hình") == nil) }),
            ]
            end = 14.5
        }
        if let e = ext(), let target = ModeCatalog.hidpiCounterpart(e.modes, current: e.current, hidpi: !e.current.resolution.isHiDPI) {
            let wasHiDPI = e.current.resolution.isHiDPI
            steps += [
                (end, { _ = click("HiDPI \(extName)") }),
                (end + 3, { check("công tắc HiDPI → \(target.label) \(target.isHiDPI ? "HiDPI" : "thường")",
                                  ext()?.current.resolution == target)
                            check("đổi HiDPI chờ xác nhận", app.pending != nil)
                            app.revertPending() }),
                (end + 6, { check("hoàn tác → HiDPI trở lại như cũ", ext()?.current.resolution.isHiDPI == wasHiDPI) }),
            ]
            end += 6.5
        }
        if let e = ext(), e.canRotate, MonitorPanel.canRotateAtAll {
            steps += [
                (end, { _ = click("Xoay \(extName) 180 độ") }),
                (end + 3, { check("chọn 180° → màn xoay 180°", ext()?.rotation == 180) }),
                // Không bấm gì: hết 15 giây phải tự về góc cũ.
                (end + 19, { check("không xác nhận → tự hoàn tác về 0° sau 15 giây",
                                   ext()?.rotation == 0 && app.pending == nil) }),
            ]
            end += 19.5
        }
        // Tỉ lệ, màn chính, phản chiếu (cũng trên màn ngoài; trả lại như cũ).
        if let e = ext() {
            let originalBounds = e.bounds, originalRes = e.current.resolution
            let groups = ModeCatalog.aspectGroups(e.modes)
            if let g43 = groups.first(where: { $0.label == "4:3" }),
               let r43 = ModeCatalog.resolution(for: g43, modes: e.modes, current: e.current) {
                steps += [
                    (end, { _ = click("Tỉ lệ 4:3 \(e.name)") }),
                    (end + 3, { check("chọn tỉ lệ 4:3 → \(r43.label)", ext()?.current.resolution == r43)
                                app.revertPending() }),
                    (end + 6, { check("hoàn tác tỉ lệ → \(originalRes.label)", ext()?.current.resolution == originalRes) }),
                ]
                end += 6.5
            }
            steps += [
                (end, { withAnimation(PopoverView.expand) { layout.toolsOpen = true; layout.openTool = "arrange" } }),
                (end + 1, { _ = click("Màn chính \(extName)") }),
                (end + 4, { check("chọn màn chính → \(extName) là màn chính", ext()?.isMain == true)
                            check("popover vẫn mở sau khi đổi màn chính", c.isShown)
                            _ = click("Màn chính Tích hợp") }),
                (end + 7, { check("đổi lại → màn tích hợp là màn chính", app.displays.first(where: \.isMain)?.isBuiltIn == true)
                            check("vị trí màn ngoài như cũ \(originalBounds)", ext()?.bounds == originalBounds)
                            _ = click("Phản chiếu màn hình") }),
                (end + 12, { check("bật phản chiếu", app.isMirroring)
                             check("icon phát sáng của Phản chiếu hiện", find("Tắt phản chiếu") != nil)
                             _ = click("Tắt phản chiếu") }),
                (end + 18, { check("bấm icon phát sáng → tắt phản chiếu (mở rộng)", !app.isMirroring)
                             check("màn ngoài về vị trí cũ (\(ext()?.bounds ?? .zero))", ext()?.bounds == originalBounds)
                             check("màn ngoài về độ phân giải cũ (\(ext()?.current.resolution.label ?? "?"))",
                                   ext()?.current.resolution == originalRes) }),
            ]
            end += 18.5
        }
        steps.append((end, {
            // Dọn: dù bước nào hỏng cũng trả màn về như cũ trước khi thoát.
            if app.isMirroring { app.setMirroring(false) }
            if app.pending != nil { app.revertPending() }
            if let mac = app.displays.first(where: \.isBuiltIn), !mac.isMain { app.makeMain(mac) }
            if let e = ext(), e.rotation != 0 { try? MonitorPanel.setRotation(e.id, degrees: 0) }
            app.preventSleep = before
        }))
        steps.append((end + 4, {
            print(failures == 0 ? "TẤT CẢ ĐẠT" : "\(failures) lỗi")
            exit(failures == 0 ? 0 : 1)
        }))
        for (t, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { step() } }
        }
    }
}

extension DevTools {
    // MARK: Trợ năng — tìm và bấm phần tử theo nhãn trong một view

    static func axElements(_ root: AnyObject) -> [AnyObject] {
        let kids = (root.accessibilityChildren?() ?? []).map { $0 as AnyObject }
        return kids + kids.flatMap(axElements)
    }

    static func axFind(_ label: String, in view: NSView?) -> AnyObject? {
        guard let view else { return nil }
        return axElements(view).first {
            ($0.accessibilityLabel?() ?? nil) == label && !($0.isAccessibilityHidden?() ?? false)
        }
    }

    static func axValue(_ label: String, in view: NSView?) -> String? {
        // Giá trị có thể là chữ (hàng công cụ) hoặc số (công tắc): đọc kiểu Any rồi mới đổi ra chữ.
        guard let el = axFind(label, in: view) as? NSObject,
              let value = el.value(forKey: "accessibilityValue") else { return nil }
        return "\(value)"
    }

    /// Nhấn qua trợ năng (như VoiceOver): dùng cho điều khiển gốc trong Form, nơi bấm vào chữ của
    /// dòng không bật/tắt công tắc.
    @discardableResult
    static func axPress(_ label: String, in view: NSView?) -> Bool {
        guard let el = axFind(label, in: view) else { print("✗ không thấy “\(label)”"); return false }
        view?.window?.makeKey()
        return el.accessibilityPerformPress?() ?? false
    }

    /// Gửi chuột xuống/lên vào giữa phần tử — đi qua hit-testing thật của SwiftUI.
    @discardableResult
    static func axClick(_ label: String, in view: NSView?) -> Bool {
        guard let el = axFind(label, in: view), let window = view?.window, let f = el.accessibilityFrame?() else {
            print("✗ không thấy “\(label)”")
            return false
        }
        // Như người dùng: bấm icon menu bar / bấm vào cửa sổ trước thì nó mới là cửa sổ chính.
        if !window.isKeyWindow { window.makeKey() }
        let p = window.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(e)
            }
        }
        return true
    }

    /// Popover và cửa sổ cùng mở; bấm ở bên này rồi kiểm tra bên kia cập nhật theo (đồng bộ).
    static func windowSyncTest() {
        guard let c = AppDelegate.statusItem else { exit(2) }
        let app = Shared.app
        let beforeSleep = app.preventSleep
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "✓ " : "✗ ") + name)
            if !ok { failures += 1 }
        }
        let win = { MainWindowController.shared.windowContentView }
        let pop = { c.panelContentView }
        guard let ext = app.displays.first(where: { !$0.isBuiltIn }) else { print("cần màn ngoài"); exit(2) }
        let name = ext.name

        let steps: [(Double, () -> Void)] = [
            (1.0, { MainWindowController.shared.show()
                    c.openOnExternalForTesting()
                    c.layout.toolsOpen = true }),
            (2.5, {
                    check("cửa sổ mở khi chạy", MainWindowController.shared.isVisible)
                    MainWindowController.shared.nav.selection = .display(ext.id) }),
            (3.0, { c.openOnExternalForTesting(); c.layout.toolsOpen = true; c.layout.openTool = "rotate" }),
            (4.0, { axClick("Xoay \(name) 90 độ", in: pop()) }),
            (7.0, { check("xoay từ popover → màn xoay 90°", app.displays.first { $0.id == ext.id }?.rotation == 90)
                    check("cửa sổ cập nhật: Xoay = “\(axValue("Xoay \(name) (cửa sổ)", in: win()) ?? "nil")”",
                          axValue("Xoay \(name) (cửa sổ)", in: win())?.contains("90") == true)
                    check("thanh “Giữ…?” hiện ở cả popover và cửa sổ",
                          axFind("Hoàn tác", in: pop()) != nil && axFind("Hoàn tác", in: win()) != nil)
                    axPress("Hoàn tác", in: win()) }),
            (10.0, { check("hoàn tác từ cửa sổ → màn về 0°", app.displays.first { $0.id == ext.id }?.rotation == 0)
                     check("thanh “Giữ…?” ở popover biến mất theo", axFind("Hoàn tác", in: pop()) == nil)
                     app.preventSleep = true
                     MainWindowController.shared.nav.selection = .tools
                     c.openOnExternalForTesting() }),
            (11.0, { axClick("Ngăn ngủ", in: pop()) }),
            (12.0, { check("tắt Ngăn ngủ từ popover", !app.preventSleep)
                     check("cửa sổ cập nhật: công tắc Ngăn ngủ = \(axValue("Ngăn ngủ", in: win()) ?? "nil")",
                           axValue("Ngăn ngủ", in: win()) == "0")
                     axPress("Ngăn ngủ", in: win()) }),
            (13.0, { check("bật Ngăn ngủ từ cửa sổ", app.preventSleep)
                     check("popover hiện icon phát sáng theo", axFind("Tắt Ngăn ngủ", in: pop()) != nil) }),
            (13.6, {
                if app.pending != nil { app.revertPending() }
                if let e = app.displays.first(where: { $0.id == ext.id }), e.rotation != 0 { try? MonitorPanel.setRotation(e.id, degrees: 0) }
                app.preventSleep = beforeSleep
                MainWindowController.shared.close()
            }),
            (14.6, { check("đóng cửa sổ → app trở lại chạy nền (không Dock)", NSApp.activationPolicy() == .accessory)
                     print(failures == 0 ? "TẤT CẢ ĐẠT" : "\(failures) lỗi")
                     exit(failures == 0 ? 0 : 1) }),
        ]
        for (t, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { step() } }
        }
    }
}

extension DevTools {
    /// Chụp cửa sổ Lumina ra PNG: `--window-snapshot <file> [display|tools|general]`.
    static func windowSnapshot(to path: String, pane: String) {
        let app = Shared.app
        MainWindowController.shared.show()
        switch pane {
        case "tools": MainWindowController.shared.nav.selection = .tools
        case "general": MainWindowController.shared.nav.selection = .general
        case "builtin": MainWindowController.shared.nav.selection = app.displays.first { $0.isBuiltIn }.map { .display($0.id) }
        default: MainWindowController.shared.nav.selection = app.displays.first { !$0.isBuiltIn }.map { .display($0.id) }
        }
        if let h = ProcessInfo.processInfo.environment["SNAPSHOT_HEIGHT"].flatMap(Double.init) {
            MainWindowController.shared.setContentSizeForSnapshot(NSSize(width: 920, height: h))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let view = MainWindowController.shared.windowContentView?.superview ?? MainWindowController.shared.windowContentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("window → \(path)")
            exit(0)
        }
    }
}

extension DevTools {
    /// Popover trên màn tích hợp (thấp nhất) với mục Công cụ + bản đồ mở: tấm kính phải nằm trọn trong màn.
    static func fitTest() {
        guard let c = AppDelegate.statusItem else { exit(2) }
        guard let mac = NSScreen.screens.first(where: { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } == true }) else { exit(2) }
        // Chiều cao tối đa nếu popover neo dưới menu bar của màn tích hợp.
        let limit = mac.visibleFrame.height - PopoverPlacement.gap - PopoverPlacement.margin
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            c.openOnExternalForTesting()
            c.layout.maxHeight = limit
            c.layout.toolsOpen = true
            c.layout.openTool = "arrange"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let h = c.renderedGlassHeight() ?? .infinity
            print("giới hạn màn tích hợp \(Int(limit)) pt · kính \(Int(h)) pt · ngân sách danh sách công cụ \(Int(c.layout.toolsBudget)) pt")
            let fits = h <= limit + 0.5
            print(fits ? "✓ popover vừa màn tích hợp, danh sách công cụ tự cuộn" : "✗ popover cao hơn màn tích hợp")
            exit(fits ? 0 : 1)
        }
    }
}

extension DevTools {
    /// Đồng bộ độ sáng trên màn thật: bật bằng cú bấm, đổi độ sáng màn tích hợp từ ngoài Lumina
    /// (như phím độ sáng), đọc ngược độ sáng phần cứng của màn ngoài qua DDC, thử bù và tắt nhanh.
    static func syncTest() {
        guard let c = AppDelegate.statusItem else { exit(2) }
        let app = Shared.app
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "✓ " : "✗ ") + name)
            if !ok { failures += 1 }
        }
        guard let mac = app.displays.first(where: \.isBuiltIn), let ext = app.displays.first(where: { !$0.isBuiltIn }) else {
            print("cần màn tích hợp + màn ngoài"); exit(2)
        }
        let beforeSync = app.brightnessSync
        let beforeProfiles = app.nitsProfiles
        var macBefore = 0.0, extBefore = 0.0
        let pop = { c.panelContentView }
        func setMacOutsideLumina(_ v: Double) { _ = PrivateAPI.displayServicesSetBrightness?(mac.id, Float(v)) }
        func expectedExt(_ macValue: Double) -> Double {
            BrightnessSync.target(sourceValue: macValue, source: app.profile(for: mac), target: app.profile(for: ext))
        }
        func readExtHardware(_ done: @escaping (Double?) -> Void) {
            Task { @MainActor in
                let s = await app.brightnessService.read(ext)
                done(s.kind == .hardware ? s.value : nil)
            }
        }

        let steps: [(Double, () -> Void)] = [
            (1.5, { macBefore = app.brightness[mac.id]?.value ?? 0.5
                    extBefore = app.brightness[ext.id]?.value ?? 0.5
                    app.brightnessSync = false
                    c.openOnExternalForTesting()
                    c.layout.toolsOpen = true }),
            (2.5, { axClick("Đồng bộ độ sáng", in: pop()) }),
            (4.5, { check("bấm hàng Đồng bộ → bật", app.brightnessSync)
                    let want = expectedExt(app.brightness[mac.id]?.value ?? 0)
                    let got = app.brightness[ext.id]?.value ?? -1
                    check(String(format: "Kuycon theo nit của MacBook: %.0f%% (cần %.0f%%) · MacBook ≈ %.0f nit, Kuycon ≈ %.0f nit",
                                 got * 100, want * 100, app.nits(for: mac) ?? 0, app.nits(for: ext) ?? 0), abs(got - want) < 0.01)
                    check("icon phát sáng của Đồng bộ hiện", axFind("Tắt đồng bộ độ sáng", in: pop()) != nil)
                    // Như bấm phím độ sáng: đổi màn tích hợp không qua Lumina.
                    setMacOutsideLumina(max(macBefore - 0.2, 0.15)) }),
            (6.5, { let m = app.brightness[mac.id]?.value ?? -1
                    check(String(format: "Lumina thấy MacBook đổi từ ngoài → %.0f%%", m * 100), abs(m - max(macBefore - 0.2, 0.15)) < 0.01)
                    let want = expectedExt(m)
                    readExtHardware { hw in
                        check(String(format: "màn Kuycon thật (đọc DDC) = %.0f%%, cần %.0f%%", (hw ?? -1) * 100, want * 100),
                              hw.map { abs($0 - want) < 0.02 } ?? false)
                    } }),
            (8.0, { // Kéo Kuycon sáng hơn 10% cho khớp mắt → thành mức bù.
                    let k = (app.brightness[ext.id]?.value ?? 0) + 0.1
                    app.setBrightness(k, for: ext)
                    check(String(format: "kéo Kuycon trong lúc đồng bộ → nhớ bù %+.0f%%", (app.profile(for: ext).ratio - 1) * 100),
                          app.profile(for: ext).ratio > 1.01)
                    setMacOutsideLumina(macBefore) }),
            (10.0, { let want = expectedExt(app.brightness[mac.id]?.value ?? 0)
                     check("đổi MacBook lần nữa → Kuycon vẫn giữ mức bù", abs((app.brightness[ext.id]?.value ?? -1) - want) < 0.01)
                     app.updateProfile(ext) { $0.ratio = 1 }
                     check("màn MacBook nhận là XDR: tối đa \(Int(app.profile(for: mac).maxNits)) nit", app.profile(for: mac).maxNits == 600)
                     setMacOutsideLumina(1) }),
            (12.0, { let m = app.brightness[mac.id]?.value ?? -1
                     check(String(format: "MacBook kéo hết 100%% (≈ %.0f nit), không bị giữ lại", app.nits(for: mac) ?? 0), m > 0.995)
                     check("Kuycon đứng ở tối đa, ghi “kịch max”", (app.brightness[ext.id]?.value ?? 0) > 0.995 && app.syncLimit(for: ext) == .atMax)
                     check("hàng Đồng bộ ghi “\(axValue("Đồng bộ độ sáng", in: pop()) ?? "nil")”",
                           axValue("Đồng bộ độ sáng", in: pop())?.contains("kịch 500") == true)
                     // Kéo Kuycon lên hết cỡ: chỉ là "sáng nhất", không phải bù.
                     app.setBrightness(1, for: ext)
                     check("kéo Kuycon tới max không lưu bù", app.profile(for: ext).ratio == 1)
                     setMacOutsideLumina(0.15) }),
            (14.0, { let m = app.brightness[mac.id]?.value ?? -1
                     check(String(format: "MacBook tối tới 15%% (≈ %.0f nit), không bị giữ lại", app.nits(for: mac) ?? 0), abs(m - 0.15) < 0.01)
                     check("Kuycon đứng ở tối nhất, ghi “tối nhất”", (app.brightness[ext.id]?.value ?? 1) < 0.005 && app.syncLimit(for: ext) == .atMin)
                     setMacOutsideLumina(macBefore)
                     axClick("Tắt đồng bộ độ sáng", in: pop()) }),
            (15.0, { check("bấm icon phát sáng → tắt đồng bộ", !app.brightnessSync)
                     // Dọn: trả độ sáng, hồ sơ nit và trạng thái đồng bộ như cũ.
                     for (key, _) in app.nitsProfiles where beforeProfiles[key] == nil {
                         if let d = app.displays.first(where: { $0.identity.key == key }) { app.resetProfile(d) }
                     }
                     setMacOutsideLumina(macBefore)
                     app.setBrightness(extBefore, for: ext)
                     app.brightnessSync = beforeSync }),
            (16.5, { print(failures == 0 ? "TẤT CẢ ĐẠT" : "\(failures) lỗi")
                     exit(failures == 0 ? 0 : 1) }),
        ]
        for (t, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { step() } }
        }
    }
}

extension DevTools {
    /// HDR + màu trên màn ngoài thật: bật HDR từ popover → cửa sổ hiện theo, tắt từ cửa sổ → popover theo;
    /// chỉnh điểm trắng rồi khôi phục (đọc ngược DDC); gán Display P3. Trả mọi thứ như cũ.
    static func colorTest() {
        guard let c = AppDelegate.statusItem else { exit(2) }
        let app = Shared.app
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "✓ " : "✗ ") + name)
            if !ok { failures += 1 }
        }
        guard let ext0 = app.displays.first(where: { !$0.isBuiltIn }) else { print("cần màn ngoài"); exit(2) }
        let ext = { app.displays.first { $0.id == ext0.id } }
        let hdrBefore = ext0.hdrOn
        let pop = { c.panelContentView }
        let win = { MainWindowController.shared.windowContentView }
        func edr() -> Double {
            Double(NSScreen.screens.first { $0.displayID == ext0.id }?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0)
        }
        func readDDC(_ code: UInt8, _ done: @escaping (Int?) -> Void) {
            Task { @MainActor in done(await app.brightnessService.readVCP(code, on: ext0).map { Int($0.current) }) }
        }
        var wbBefore: WhiteBalance?
        // Giá trị gốc đã lưu (của người dùng) — test không được làm mất nó.
        let originalKey = "whiteBalance." + ext0.identity.key
        let savedOriginal = UserDefaults.standard.data(forKey: originalKey)

        let steps: [(Double, () -> Void)] = [
            (1.0, { check("\(ext0.name) hỗ trợ HDR", ext0.hasHDR)
                    if hdrBefore { app.setHDR(ext0, on: false) }
                    MainWindowController.shared.show()
                    MainWindowController.shared.nav.selection = .display(ext0.id)
                    c.openOnExternalForTesting() }),
            (4.0, { axClick("HDR \(ext0.name)", in: pop()) }),
            (8.0, { check("bật HDR từ popover", ext()?.hdrOn == true)
                    check(String(format: "màn nhận HDR: khoảng HDR %.0f×", edr()), edr() > 1)
                    check("cửa sổ hiện HDR bật theo (\(axValue("HDR \(ext0.name)", in: win()) ?? "nil"))",
                          ["1", "on"].contains(axValue("HDR \(ext0.name)", in: win()) ?? ""))
                    axPress("HDR \(ext0.name)", in: win()) }),
            (12.0, { check("tắt HDR từ cửa sổ", ext()?.hdrOn == false)
                     // NSScreen giữ khoảng HDR cũ trong cùng tiến trình sau khi tắt; đọc thẳng từ MonitorPanel.
                     check("màn về SDR (MonitorPanel: HDR \(MonitorPanel.info()[ext0.id]?.hdrOn == true ? "bật" : "tắt"))",
                           MonitorPanel.info()[ext0.id]?.hdrOn == false)
                     wbBefore = app.whiteBalance[ext0.id]
                     check("đọc điểm trắng qua DDC: \(wbBefore.map { "\($0.red)/\($0.green)/\($0.blue)" } ?? "nil")", wbBefore != nil)
                     if var w = wbBefore { w.red += 1; app.setWhiteBalance(w, for: ext0) } }),
            (13.5, { readDDC(0x16) { r in
                         check("chỉnh Đỏ +1 → màn thật = \(r ?? -1)", r == (wbBefore?.red ?? -9) + 1)
                         check("có giá trị gốc để khôi phục", app.originalWhiteBalance(ext0) != nil)
                         // Trả đúng số lúc bắt đầu (không gọi Khôi phục: nó về giá trị gốc của người dùng)
                         if let w = wbBefore { app.setWhiteBalance(w, for: ext0) }
                     } }),
            (15.0, { readDDC(0x16) { r in
                         check("trả về như lúc đầu → màn thật = \(r ?? -1)", r == wbBefore?.red)
                         // Giữ nguyên bản ghi giá trị gốc của người dùng như trước khi test
                         if let savedOriginal { UserDefaults.standard.set(savedOriginal, forKey: originalKey) }
                         else { UserDefaults.standard.removeObject(forKey: originalKey) }
                     }
                     app.useDisplayP3(ext0) }),
            (17.0, { check("hồ sơ màu = \(ColorService.profileName(ext0.id) ?? "nil")", ColorService.usesDisplayP3(ext0.id))
                     check("không có lỗi", app.errorMessage == nil)
                     if let e = ext(), e.hdrOn != hdrBefore { app.setHDR(e, on: hdrBefore) }
                     MainWindowController.shared.close() }),
            (19.0, { print(failures == 0 ? "TẤT CẢ ĐẠT" : "\(failures) lỗi")
                     exit(failures == 0 ? 0 : 1) }),
        ]
        for (t, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { step() } }
        }
    }
}
