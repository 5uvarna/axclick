// Renders the app icon (app/AppIcon.icns) and docs/logo.png from the axe in app/Logo.swift.
// Run from the repository root after changing the logo:
//
//   swiftc app/Logo.swift scripts/make-icon/main.swift -o /tmp/make-icon && /tmp/make-icon

import AppKit

func png(_ pixels: Int, padded: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Flip to a top-left origin, like the SVG.
    context.cgContext.translateBy(x: 0, y: CGFloat(pixels))
    context.cgContext.scaleBy(x: 1, y: -1)
    let size = CGFloat(pixels)
    // macOS app icons leave a margin around the rounded square (100 of 1024 on each side).
    let inset = padded ? size * 100 / 1024 : 0
    drawLogo(in: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(points, padded: true).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2, padded: true).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "app/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try png(512, padded: false).write(to: URL(fileURLWithPath: "docs/logo.png"))
print(iconutil.terminationStatus == 0 ? "wrote app/AppIcon.icns and docs/logo.png" : "iconutil failed")
