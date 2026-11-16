// Draws the 1024pt app icon: two offset glass panes over a dusk gradient.
import AppKit

let size = 1024.0
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let outputPath = CommandLine.arguments[1]

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let body = canvas.insetBy(dx: 100, dy: 100)
let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [
    NSColor(red: 0.13, green: 0.10, blue: 0.42, alpha: 1),
    NSColor(red: 0.42, green: 0.20, blue: 0.78, alpha: 1),
    NSColor(red: 0.98, green: 0.52, blue: 0.47, alpha: 1),
])!.draw(in: body, angle: 60)

func pane(_ rect: CGRect, alpha: Double) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 52, yRadius: 52)
    NSColor.white.withAlphaComponent(alpha).setFill()
    path.fill()
    path.lineWidth = 8
    NSColor.white.withAlphaComponent(0.65).setStroke()
    path.stroke()
}
pane(CGRect(x: 250, y: 400, width: 470, height: 310), alpha: 0.18)
pane(CGRect(x: 310, y: 320, width: 470, height: 310), alpha: 0.30)

let play = NSBezierPath()
play.move(to: CGPoint(x: 498, y: 395))
play.line(to: CGPoint(x: 498, y: 555))
play.line(to: CGPoint(x: 628, y: 475))
play.close()
NSColor.white.setFill()
play.fill()
NSGraphicsContext.restoreGraphicsState()

try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
