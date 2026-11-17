// Vẽ icon Lumina bằng CoreGraphics + CoreImage rồi xuất Resources/AppIcon.icns (16…1024).
// Cách dùng: swift scripts/make-icon.swift [--preview <file.png>]
// Ngoài .icns còn xuất Resources/Icons/: AppIcon-<cỡ>.png (16…1024) và MenuBarIcon@1x/@2x/@4x.png
// (icon menu bar cùng hình, vẽ bằng cùng hàm `trefoil`) để xem được icon ngay trên GitHub.
//
// Hình: khối kính ba cánh (trefoil) màu chuyển cyan → xanh → tím trên nền sáng pastel (kiểu macOS 26/27),
// lõi trong phát sáng trắng, ba mặt nối vào một tâm sáng như góc một khối lập phương.
// Vẽ bằng code (không SVG) vì CoreSVG không làm được lớp kính mờ và quầng sáng.
import AppKit
import CoreImage

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let S: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: srgb])

func rgba(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// MARK: Hình học

/// Squircle (góc liên tục) theo khung icon macOS: 824 pt giữa canvas 1024.
func squircle(_ rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    let n: CGFloat = 4.2, steps = 360
    let a = rect.width / 2, b = rect.height / 2, c = CGPoint(x: rect.midX, y: rect.midY)
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = c.x + a * (ct >= 0 ? 1 : -1) * pow(abs(ct), 2 / n)
        let y = c.y + b * (st >= 0 ? 1 : -1) * pow(abs(st), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

/// Đa giác bo góc (mọi góc cùng bán kính).
func rounded(_ pts: [CGPoint], radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = pts.count
    let start = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2)
    p.move(to: start)
    for i in 0..<n {
        p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radius)
    }
    p.closeSubpath()
    return p
}

/// Ba cánh hướng 90°, 210°, 330° (toạ độ y hướng lên). Mỗi cánh đầu bằng (rộng `tipHalf` rad),
/// giữa hai cánh là khe lõm ở bán kính `notch`.
func trefoil(center c: CGPoint, tip R: CGFloat, notch r: CGFloat, tipHalf d: CGFloat, radius: CGFloat) -> CGPath {
    var pts: [CGPoint] = []
    for k in 0..<3 {
        let th = CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 3
        pts.append(CGPoint(x: c.x + R * cos(th - d), y: c.y + R * sin(th - d)))
        pts.append(CGPoint(x: c.x + R * cos(th + d), y: c.y + R * sin(th + d)))
        let nt = th + .pi / 3
        pts.append(CGPoint(x: c.x + r * cos(nt), y: c.y + r * sin(nt)))
    }
    return rounded(pts, radius: radius)
}

// MARK: Vẽ

func blurred(_ image: CGImage, radius: CGFloat) -> CGImage {
    let input = CIImage(cgImage: image).clampedToExtent()
    let out = input.applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: S, height: S))
    return ci.createCGImage(out, from: out.extent)!
}

func layer(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func linear(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from a: CGPoint, to b: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func radial(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], locations: [CGFloat], center: CGPoint, radius: CGFloat) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func renderMaster() -> CGImage {
    let frame = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bg = squircle(frame)
    let c = CGPoint(x: 512, y: 530)
    let glass = trefoil(center: c, tip: 302, notch: 152, tipHalf: 0.31, radius: 58)
    let slab = trefoil(center: CGPoint(x: c.x, y: c.y - 16), tip: 302, notch: 152, tipHalf: 0.31, radius: 58)
    let core = trefoil(center: c, tip: 196, notch: 96, tipHalf: 0.32, radius: 40)

    // Ánh sáng trắng toả từ lõi (mềm, không viền cứng)
    let bloom = blurred(layer { ctx in
        ctx.addPath(core); ctx.setFillColor(rgba(0xFFFFFF, 1)); ctx.fillPath()
    }, radius: 34)
    // Bóng màu chàm dưới khối kính
    let shadow = blurred(layer { ctx in
        ctx.addPath(trefoil(center: CGPoint(x: c.x, y: c.y - 70), tip: 270, notch: 136, tipHalf: 0.31, radius: 58))
        ctx.setFillColor(rgba(0x4B3BFF, 0.42)); ctx.fillPath()
    }, radius: 46)
    // Vệt pastel trên nền
    let blobs = blurred(layer { ctx in
        ctx.setFillColor(rgba(0x6FD3FF, 0.55)); ctx.fillEllipse(in: CGRect(x: 90, y: 560, width: 420, height: 360))
        ctx.setFillColor(rgba(0xA58BFF, 0.5)); ctx.fillEllipse(in: CGRect(x: 520, y: 110, width: 420, height: 380))
    }, radius: 90)

    return layer { ctx in
        // Nền sáng gần trắng + vệt pastel
        ctx.saveGState(); ctx.addPath(bg); ctx.clip()
        linear(ctx, bg, [rgba(0xFDFDFF), rgba(0xEEF0F8), rgba(0xE2E5F2)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
        ctx.setAlpha(0.65); ctx.draw(blobs, in: CGRect(x: 0, y: 0, width: S, height: S)); ctx.setAlpha(1)
        ctx.draw(shadow, in: CGRect(x: 0, y: 0, width: S, height: S))
        ctx.restoreGState()

        // Bề dày tấm kính (mép dưới)
        linear(ctx, slab, [rgba(0x4A6BF0, 0.9), rgba(0x5A3FD8, 0.95)], from: CGPoint(x: 300, y: 820), to: CGPoint(x: 720, y: 220))
        // Mặt kính: chuyển cyan → xanh → tím, hơi trong
        linear(ctx, glass, [rgba(0x7ADFFF, 0.96), rgba(0x5B86FF, 0.94), rgba(0x8B5CFF, 0.95)],
               from: CGPoint(x: 260, y: 860), to: CGPoint(x: 760, y: 200))
        // Ánh phản chiếu nửa trên (kiểu Liquid Glass)
        ctx.saveGState(); ctx.addPath(glass); ctx.clip()
        let sheen = CGGradient(colorsSpace: srgb, colors: [rgba(0xFFFFFF, 0.55), rgba(0xFFFFFF, 0.08), rgba(0xFFFFFF, 0)] as CFArray,
                               locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 840), end: CGPoint(x: 512, y: 470), options: [])
        // Ánh sáng lõi toả lên mặt kính
        ctx.setAlpha(0.9); ctx.draw(bloom, in: CGRect(x: 0, y: 0, width: S, height: S))
        ctx.restoreGState()
        // Viền sáng mảnh, đậm ở trên-trái
        ctx.saveGState(); ctx.addPath(glass); ctx.setLineWidth(7); ctx.replacePathWithStrokedPath(); ctx.clip()
        let rim = CGGradient(colorsSpace: srgb, colors: [rgba(0xFFFFFF, 0.95), rgba(0xFFFFFF, 0.2), rgba(0xFFFFFF, 0.5)] as CFArray,
                             locations: [0, 0.6, 1])!
        ctx.drawLinearGradient(rim, start: CGPoint(x: 280, y: 860), end: CGPoint(x: 740, y: 200), options: [])
        ctx.restoreGState()

        // Lõi: trắng sáng, rìa hơi xanh băng, không viền cứng
        radial(ctx, core, [rgba(0xFFFFFF), rgba(0xFFFFFF), rgba(0xE6F1FF)], locations: [0, 0.55, 1], center: c, radius: 210)
        // Ba gân rất mờ (gợi khối), không còn đường trắng cứng
        ctx.saveGState(); ctx.addPath(core); ctx.clip()
        for k in 0..<3 {
            let th = CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / 3
            ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + 220 * cos(th), y: c.y + 220 * sin(th)))
        }
        ctx.setStrokeColor(rgba(0x7A8CFF, 0.22)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: Xuất

let master = renderMaster()

func png(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    try png(1024).write(to: URL(fileURLWithPath: args[i + 1]))
    print("preview → \(args[i + 1])")
    exit(0)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let icons = root.appendingPathComponent("Resources/Icons")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    try png(px).write(to: icons.appendingPathComponent("AppIcon-\(px).png"))
}
// Icon menu bar (template đen trên nền trong), cùng hình với MenuBarIcon.draw() trong app:
// viền ba cánh + lõi đặc. Toạ độ 18×18 với y hướng lên (app vẽ y hướng xuống, tâm ở y = 9.7).
func glyph(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 18, y: CGFloat(px) / 18)
    let c = CGPoint(x: 9, y: 18 - 9.7)
    ctx.addPath(trefoil(center: c, tip: 8.4, notch: 4.2, tipHalf: 0.30, radius: 1.5))
    ctx.setStrokeColor(rgba(0x000000)); ctx.setLineWidth(1.25); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.addPath(trefoil(center: c, tip: 4.7, notch: 2.35, tipHalf: 0.31, radius: 0.8))
    ctx.setFillColor(rgba(0x000000)); ctx.fillPath()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}
for (suffix, px) in [("@1x", 18), ("@2x", 36), ("@4x", 72)] {
    try glyph(px).write(to: icons.appendingPathComponent("MenuBarIcon\(suffix).png"))
}
print("png → \(icons.path)")

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil lỗi \(p.terminationStatus)") }
try? FileManager.default.removeItem(at: iconset)
print("icns → \(out.path)")
