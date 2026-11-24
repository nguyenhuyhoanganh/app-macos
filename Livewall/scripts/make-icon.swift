// Draws the 1024pt app icon: a light glass tile with two screens, the front one blue
// with a play button. Run through scripts/make-icon.sh, which builds the .icns.
import AppKit

let size = 1024
let outputPath = CommandLine.arguments[1]

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

/// Straight sides with superellipse corners, like Apple's continuous-corner icon shape.
func squircle(center c: CGPoint, half a: CGFloat, radius r: CGFloat, exponent n: CGFloat = 3, steps: Int = 64) -> NSBezierPath {
    let path = NSBezierPath()
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(1, 1, 0, 90), (-1, 1, 90, 180), (-1, -1, 180, 270), (1, -1, 270, 360)]
    for (sx, sy, t0, t1) in corners {
        let ox = c.x + sx * (a - r)
        let oy = c.y + sy * (a - r)
        for i in 0...steps {
            let t = (t0 + (t1 - t0) * CGFloat(i) / CGFloat(steps)) * .pi / 180
            let point = CGPoint(
                x: ox + r * copysign(pow(abs(cos(t)), 2 / n), cos(t)),
                y: oy + r * copysign(pow(abs(sin(t)), 2 / n), sin(t))
            )
            if path.isEmpty { path.move(to: point) } else { path.line(to: point) }
        }
    }
    path.close()
    return path
}

func shadow(alpha: CGFloat, blur: CGFloat, y: CGFloat) -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    return shadow
}

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// The 824pt body of Apple's icon grid, with a soft shadow under it.
let body = squircle(center: CGPoint(x: 512, y: 512), half: 412, radius: 280)
NSGraphicsContext.saveGraphicsState()
shadow(alpha: 0.32, blur: 28, y: -12).set()
rgb(0xd6dbe4).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
body.addClip()
NSGradient(starting: rgb(0xfbfbfd), ending: rgb(0xd6dbe4))!.draw(in: body.bounds, angle: -90)
NSGradient(starting: rgb(0xffffff, 0.5), ending: rgb(0xffffff, 0))!
    .draw(in: CGRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

func screen(_ rect: CGRect) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: 56, yRadius: 56) }
let back = screen(CGRect(x: 236, y: 418, width: 480, height: 312))
let front = screen(CGRect(x: 308, y: 316, width: 480, height: 312))

rgb(0x0a84ff, 0.10).setFill()
back.fill()
back.lineWidth = 7
rgb(0x0a84ff, 0.34).setStroke()
back.stroke()

NSGraphicsContext.saveGraphicsState()
shadow(alpha: 0.28, blur: 30, y: -10).set()
rgb(0x5e5ce6).setFill()
front.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
front.addClip()
NSGradient(starting: rgb(0x40a9ff), ending: rgb(0x5e5ce6))!.draw(in: front.bounds, angle: -90)
NSGradient(starting: rgb(0xffffff, 0.22), ending: rgb(0xffffff, 0))!
    .draw(in: CGRect(x: 308, y: 472, width: 480, height: 156), angle: -90)
NSGraphicsContext.restoreGraphicsState()
front.lineWidth = 7
rgb(0xffffff, 0.85).setStroke()
front.stroke()

// A filled triangle stroked with round joins, so its corners are softened.
let play = NSBezierPath()
play.move(to: CGPoint(x: 512, y: 404))
play.line(to: CGPoint(x: 512, y: 540))
play.line(to: CGPoint(x: 624, y: 472))
play.close()
play.lineJoinStyle = .round
play.lineWidth = 22
NSColor.white.setFill()
NSColor.white.setStroke()
play.fill()
play.stroke()

// A thin bright rim just inside the edge.
body.lineWidth = 8
rgb(0xffffff, 0.6).setStroke()
body.stroke()
NSGraphicsContext.restoreGraphicsState()

try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
