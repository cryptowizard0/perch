import AppKit

// Perch's app icon: a pixel bird perched on the notch (Perch's collapsed panel, with its orange status dot),
// on the README's wallpaper gradient. Writes a macOS .iconset (16–1024 px); scripts/icon/make-icon.sh turns it
// into packaging/Perch.icns.
// usage: swift draw-icon.swift <out.iconset>
let args = CommandLine.arguments
let iconset = URL(fileURLWithPath: args[1])

// The bird, facing right. B body, W wing, C chest, E eye, H eye highlight, K beak, L legs, T tail.
let bird = [
    "................",
    "......BBBB......",
    ".....BBBBBB.....",
    "....BBBBBEHB....",
    "....BBBBBEEBKK..",
    "....BBBBBBBBK...",
    "...BBBBBBBBB....",
    "..WWWBBBCCCC....",
    "TWWWWWBCCCCC....",
    "TTWWWWWCCCCC....",
    ".TTWWWWCCCCC....",
    "...WWWWCCCC.....",
    "....BBBBBB......",
    "......L..L......",
    "......L..L......",
    "................",
]

struct Palette { var body, wing, chest, beak, legs, eye: NSColor }
func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
// Cream bird; beak and legs in the status dot's orange.
let p = Palette(body: hex(0xF4EBDD), wing: hex(0xC9B8A2), chest: hex(0xFFF8EE), beak: hex(0xFF9419), legs: hex(0xFF9419),
                eye: hex(0x16161A))

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

// The perch: Perch's collapsed notch, flat on top, rounded below, with its orange status dot.
let bar = CGRect(x: 232, y: 600, width: 560, height: 128)
NSColor.black.setFill()
NSBezierPath(roundedRect: bar, xRadius: 46, yRadius: 46).fill()
ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: 46))
let dot = CGRect(x: bar.minX + 56, y: bar.midY - 22, width: 44, height: 44)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24, color: hex(0xFF9419).withAlphaComponent(0.9).cgColor)
hex(0xFF9419).setFill()
NSBezierPath(ovalIn: dot).fill()
ctx.restoreGState()

// The bird, standing on the bar: crisp square cells.
let cell: CGFloat = 26
let birdOrigin = CGPoint(x: bar.midX - cell * 8 + cell * 1.5, y: bar.minY - cell * 15)  // legs end on the bar
ctx.setShouldAntialias(false)
for (y, row) in bird.enumerated() {
    for (x, ch) in row.enumerated() {
        let color: NSColor?
        switch ch {
        case "B": color = p.body
        case "W", "T": color = p.wing
        case "C": color = p.chest
        case "E": color = p.eye
        case "H": color = .white
        case "K": color = p.beak
        case "L": color = p.legs
        default: color = nil
        }
        guard let color else { continue }
        color.setFill()
        ctx.fill(CGRect(x: birdOrigin.x + CGFloat(x) * cell, y: birdOrigin.y + CGFloat(y) * cell, width: cell, height: cell))
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
