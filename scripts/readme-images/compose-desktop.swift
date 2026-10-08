import AppKit

// README images: a clean MacBook desktop (generated wallpaper, a bare menu bar) with a real capture of Perch's
// panel under the notch. Geometry is a 14" MacBook Pro (1710×1107 pt, notch 185×33 pt at x 763).
// usage: swift compose-desktop.swift <panel.png captured @2x> <out.png> <top points to keep> <output width px>
let args = CommandLine.arguments
let keepHeight = CGFloat(Double(args[3])!)
let outWidth = Int(args[4])!
let panel = NSImage(contentsOfFile: args[1])!
let panelPixels = panel.representations.first!
panel.size = NSSize(width: CGFloat(panelPixels.pixelsWide) / 2, height: CGFloat(panelPixels.pixelsHigh) / 2)
let out = args[2]

let screen = CGSize(width: 1710, height: 1107)
let size = CGSize(width: screen.width, height: keepHeight)  // only the top of the screen is drawn
let scale = CGFloat(outWidth) / screen.width
let menuBar: CGFloat = 33
let notch = CGRect(x: 763, y: 0, width: 185, height: 33)  // top-left origin

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Flip to top-left origin, like the screen.
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)
let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
NSGraphicsContext.current = flipped

// Wallpaper: a calm diagonal gradient with a soft glow.
let colors = [NSColor(srgbRed: 0.10, green: 0.16, blue: 0.36, alpha: 1).cgColor,
              NSColor(srgbRed: 0.33, green: 0.24, blue: 0.55, alpha: 1).cgColor,
              NSColor(srgbRed: 0.78, green: 0.42, blue: 0.52, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: screen.width, y: screen.height), options: [])
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(white: 1, alpha: 0.18).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: screen.width * 0.72, y: screen.height * 0.62), startRadius: 0,
                       endCenter: CGPoint(x: screen.width * 0.72, y: screen.height * 0.62), endRadius: 700, options: [])

// Menu bar: a light veil over the wallpaper, white text.
ctx.setFillColor(NSColor(white: 0, alpha: 0.22).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: menuBar))

func text(_ s: String, at x: CGFloat, bold: Bool = false) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 13, weight: bold ? .bold : .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: s, attributes: attrs)
    let w = str.size().width
    str.draw(at: CGPoint(x: x, y: (menuBar - str.size().height) / 2))
    return w
}
func symbol(_ name: String, at x: CGFloat, pointSize: CGFloat = 14) -> CGFloat {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium).applying(.init(paletteColors: [.white]))
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    image.draw(in: CGRect(x: x, y: (menuBar - image.size.height) / 2, width: image.size.width, height: image.size.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    return image.size.width
}

var x: CGFloat = 20
x += symbol("apple.logo", at: x, pointSize: 15) + 22
x += text("Finder", at: x, bold: true) + 20
for item in ["File", "Edit", "View", "Go", "Window", "Help"] { x += text(item, at: x) + 20 }

// Right side, from the edge inward: clock, control centre, Wi-Fi, battery.
let clock = "Thu Oct 8  9:41 AM"
let clockWidth = NSAttributedString(string: clock, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).size().width
var r = size.width - 16 - clockWidth
_ = text(clock, at: r)
for name in ["switch.2", "wifi", "battery.100"] {
    let config = NSImage.SymbolConfiguration(pointSize: name == "battery.100" ? 16 : 14, weight: .medium)
    let w = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!.size.width
    r -= 22 + w
    _ = symbol(name, at: r, pointSize: name == "battery.100" ? 16 : 14)
}

// The notch itself (hardware: black, rounded at the bottom).
NSColor.black.setFill()
NSBezierPath(roundedRect: notch, xRadius: 8, yRadius: 8).fill()
ctx.fill(CGRect(x: notch.minX, y: 0, width: notch.width, height: notch.height / 2))  // square top corners

// Perch's real panel, centred on the notch, hanging from the top edge.
let panelSize = CGSize(width: panel.size.width, height: panel.size.height)  // points (captured @2x)
panel.draw(in: CGRect(x: notch.midX - panelSize.width / 2, y: 0, width: panelSize.width, height: panelSize.height),
           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)
