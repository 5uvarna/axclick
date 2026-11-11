// The axe logo, drawn in code so the menu bar icon, the app icon and docs/logo.svg share one shape.
// Coordinates match docs/logo.svg: a 64×64 box with the origin at the top left.

import AppKit

/// Converts a quadratic curve (what the SVG uses) to the cubic curve NSBezierPath supports.
private func quad(_ path: NSBezierPath, to end: NSPoint, control c: NSPoint) {
    let start = path.currentPoint
    path.curve(to: end,
               controlPoint1: NSPoint(x: start.x + 2 / 3 * (c.x - start.x), y: start.y + 2 / 3 * (c.y - start.y)),
               controlPoint2: NSPoint(x: end.x + 2 / 3 * (c.x - end.x), y: end.y + 2 / 3 * (c.y - end.y)))
}

/// The axe in the 64×64 box, tilted and centered like the SVG.
func axePath() -> NSBezierPath {
    let handle = NSBezierPath(roundedRect: NSRect(x: 28.5, y: 13, width: 7, height: 45), xRadius: 3.5, yRadius: 3.5)
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 40, y: 12))
    head.line(to: NSPoint(x: 40, y: 28))
    head.line(to: NSPoint(x: 30, y: 25.5))
    quad(head, to: NSPoint(x: 7, y: 36), control: NSPoint(x: 20, y: 33))
    quad(head, to: NSPoint(x: 7, y: 5), control: NSPoint(x: 1, y: 21))
    quad(head, to: NSPoint(x: 30, y: 15.5), control: NSPoint(x: 20, y: 9))
    head.close()
    handle.append(head)

    // SVG: translate(33 35) rotate(35) scale(0.8) translate(-30 -32)
    let t = NSAffineTransform()
    t.translateX(by: 33, yBy: 35)
    t.rotate(byDegrees: 35)
    t.scale(by: 0.8)
    t.translateX(by: -30, yBy: -32)
    handle.transform(using: t as AffineTransform)
    return handle
}

/// The menu bar icon: the axe alone, as a template image so macOS tints it for light and dark menu bars.
func menuBarIcon() -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        let path = axePath()
        // Fit the axe itself (not its 64×64 box) into the icon, with a point of space around it.
        let b = path.bounds
        let scale = (size - 2) / max(b.width, b.height)
        let t = NSAffineTransform()
        t.translateX(by: size / 2, yBy: size / 2)
        t.scale(by: scale)
        t.translateX(by: -b.midX, yBy: -b.midY)
        path.transform(using: t as AffineTransform)
        NSColor.black.setFill()
        path.fill()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "axclick"
    return image
}

/// The full logo: the axe on a yellow rounded square, drawn into `rect` of a flipped (top-left) context.
func drawLogo(in rect: NSRect) {
    let s = rect.width / 64
    NSColor(srgbRed: 1, green: 0.831, blue: 0.231, alpha: 1).setFill() // #ffd43b
    NSBezierPath(roundedRect: rect, xRadius: 14 * s, yRadius: 14 * s).fill()
    let path = axePath()
    let t = NSAffineTransform()
    t.translateX(by: rect.minX, yBy: rect.minY)
    t.scale(by: s)
    path.transform(using: t as AffineTransform)
    NSColor(srgbRed: 0.086, green: 0.086, blue: 0.102, alpha: 1).setFill() // #16161a
    path.fill()
}
