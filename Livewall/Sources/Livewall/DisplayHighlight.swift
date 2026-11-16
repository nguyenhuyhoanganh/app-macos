import AppKit

/// Briefly outlines a display so it is obvious which one is being edited.
@MainActor
enum DisplayHighlight {
    private static var current: NSWindow?

    static func flash(_ screen: NSScreen) {
        current?.close()

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)
        window.contentView = OutlineView(frame: CGRect(origin: .zero, size: screen.frame.size))
        window.orderFrontRegardless()
        current = window

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.9
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                window.close()
                if current === window { current = nil }
            }
        }
    }

    private final class OutlineView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 4, dy: 4))
            path.lineWidth = 8
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
    }
}
