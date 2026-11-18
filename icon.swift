// Draws the app icon to a 1024×1024 PNG. Usage: swift icon.swift out.png
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded-square plate
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!
    .draw(in: platePath, angle: -90)

// Four coloured spots
let spots: [(NSColor, CGFloat, CGFloat)] = [
    (NSColor(red: 0.89, green: 0.15, blue: 0.17, alpha: 1), -1, 1),
    (NSColor(red: 0.10, green: 0.42, blue: 0.90, alpha: 1), 1, 1),
    (NSColor(red: 0.99, green: 0.82, blue: 0.10, alpha: 1), -1, -1),
    (NSColor(red: 0.13, green: 0.68, blue: 0.30, alpha: 1), 1, -1),
]
let offset: CGFloat = 180, radius: CGFloat = 148
for (color, dx, dy) in spots {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 + dx * offset - radius, y: 512 + dy * offset - radius,
                                width: radius * 2, height: radius * 2)).fill()
}

// Spinner needle
let ctx = NSGraphicsContext.current!.cgContext
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -.pi / 5)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.5).cgColor)
let needle = NSBezierPath()
needle.move(to: NSPoint(x: 0, y: 300))
needle.line(to: NSPoint(x: 44, y: 0))
needle.line(to: NSPoint(x: 0, y: -110))
needle.line(to: NSPoint(x: -44, y: 0))
needle.close()
NSColor.white.setFill()
needle.fill()
ctx.restoreGState()
NSColor(white: 0.12, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 512 - 20, y: 512 - 20, width: 40, height: 40)).fill()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
