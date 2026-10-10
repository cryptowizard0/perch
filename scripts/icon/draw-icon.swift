import AppKit

// Perch's app icon: the notch mascot (#22), a pixel cyclops in the Needs-you orange, hanging from the notch with its
// antenna plugged in, on the README's wallpaper gradient. Writes a macOS .iconset (16–1024 px);
// scripts/icon/make-icon.sh turns it into packaging/Perch.icns.
// usage: swift draw-icon.swift <out.iconset>
let args = CommandLine.arguments
let iconset = URL(fileURLWithPath: args[1])

// The cyclops from `Mascot` (Sources/PerchAppCore/Mascot.swift), arms stretched up to hold on. # body, w eye white, o dark.
let cyclops = [
    "#.....#.....#",
    "#.....#.....#",
    "#..#######..#",
    "#.#########.#",
    "#####www#####",
    ".###wwwww###.",
    ".###wwoww###.",
    ".###wwwww###.",
    ".####www####.",
    ".###########.",
    "..###ooo###..",
    "..#########..",
    "..##.....##..",
]

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
// Needs you's orange (`SessionStatus.color(.waiting)`); dark parts as in the notch.
let orange = hex(0xFF941A), dark = hex(0x0B0B0B)

let side = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let base = NSGraphicsContext(bitmapImageRep: rep)!
let ctx = base.cgContext
ctx.translateBy(x: 0, y: CGFloat(side))
ctx.scaleBy(x: 1, y: -1)  // top-left origin
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
ctx.interpolationQuality = .none
ctx.setShouldAntialias(true)

// macOS icon grid: an 824 pt squircle centred in 1024, with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()
ctx.saveGState()
squircle.addClip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [hex(0x1A2A5C).cgColor, hex(0x553D8C).cgColor, hex(0xC76B85).cgColor] as CFArray,
                          locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

// The notch, flush with the icon's top edge, square on top and rounded below.
let notch = CGRect(x: 262, y: 100, width: 500, height: 150)
NSColor.black.setFill()
NSBezierPath(roundedRect: notch, xRadius: 52, yRadius: 52).fill()
ctx.fill(CGRect(x: notch.minX, y: notch.minY, width: notch.width, height: 52))

// The cyclops hanging from its lower edge: crisp square cells.
let cell: CGFloat = 36
let origin = CGPoint(x: notch.midX - cell * 6.5, y: notch.maxY)
ctx.setShouldAntialias(false)
for (y, row) in cyclops.enumerated() {
    for (x, ch) in row.enumerated() {
        let color: NSColor
        switch ch {
        case "#": color = orange
        case "w": color = .white
        case "o": color = dark
        default: continue
        }
        color.setFill()
        ctx.fill(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y) * cell, width: cell, height: cell))
    }
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

// Every size macOS asks for, scaled down from the 1024 master.
let master = NSImage(size: NSSize(width: side, height: side))
master.addRepresentation(rep)
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current!.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try! small.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
print("wrote", iconset.path)
