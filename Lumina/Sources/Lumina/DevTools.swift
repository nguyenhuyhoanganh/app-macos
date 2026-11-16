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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.openOnExternalForTesting() }
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
