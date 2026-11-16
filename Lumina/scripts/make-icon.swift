// Vẽ Resources/AppIcon.svg ra Resources/AppIcon.icns (đủ cỡ 16…1024) bằng AppKit/CoreSVG.
// Cách dùng: swift scripts/make-icon.swift [--preview <file.png>]
// Ngoài .icns còn xuất Resources/Icons/: AppIcon-<cỡ>.png (16…1024) và MenuBarIcon@1x/@2x/@4x.png
// để xem được icon ngay trên GitHub.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let svg = root.appendingPathComponent("Resources/AppIcon.svg")
guard let image = NSImage(contentsOf: svg) else { fatalError("Không đọc được \(svg.path)") }

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
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
// PNG để xem trên GitHub
let icons = root.appendingPathComponent("Resources/Icons")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    try png(px).write(to: icons.appendingPathComponent("AppIcon-\(px).png"))
}
if let glyph = NSImage(contentsOf: icons.appendingPathComponent("MenuBarIcon.svg")) {
    for (suffix, px) in [("@1x", 18), ("@2x", 36), ("@4x", 72)] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        glyph.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: icons.appendingPathComponent("MenuBarIcon\(suffix).png"))
    }
}
print("png → \(icons.path)")

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { fatalError("iconutil lỗi \(p.terminationStatus)") }
try? FileManager.default.removeItem(at: iconset)   // không để lại thư mục tạm
print("icns → \(out.path)")
