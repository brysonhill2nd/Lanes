import AppKit
import Foundation

// Draws the background of the disk image window (640 × 400 points) at 1x and 2x:
// a title, an arrow made of the five category colors from the app icon, and a
// hint below. Finder draws the Lanes and Applications icons on top, at the
// centers in Tools/dmg-settings.py, with their names in black (light mode) or
// white (dark mode, where they fade into this background; the title says it all).
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let width: CGFloat = 640, height: CGFloat = 400
let iconY: CGFloat = 196, iconSize: CGFloat = 128
let appX: CGFloat = 160, applicationsX: CGFloat = 480

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// Positions below are measured from the top, like Finder's icon positions.
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: height - top - h, width: w, height: h) }
func centered(_ text: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: size > 16 ? -0.3 : 0])
    let measured = string.size()
    string.draw(at: NSPoint(x: (width - measured.width) / 2, y: height - top - measured.height))
}

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSGradient(starting: color(0xF6F7F2), ending: color(0xE9ECE4))!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    centered("Drag Lanes into Applications", top: 46, size: 22, weight: .semibold, color: color(0x1A1F1C))

    // Arrow: one short bar per category, then a chevron in the accent color.
    let lanes = [0x8DB35F, 0x6E97DB, 0xD88A50, 0x9580C4, 0x4FA8A1]
    let start = appX + iconSize / 2 + 30, bar: CGFloat = 16, gap: CGFloat = 6
    for (index, hex) in lanes.enumerated() {
        color(hex).setFill()
        NSBezierPath(roundedRect: rect(start + CGFloat(index) * (bar + gap), iconY - 3, bar, 6), xRadius: 3, yRadius: 3).fill()
    }
    let tip = start + 5 * (bar + gap) + 14
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: tip - 12, y: height - iconY + 12))
    chevron.line(to: NSPoint(x: tip, y: height - iconY))
    chevron.line(to: NSPoint(x: tip - 12, y: height - iconY - 12))
    chevron.lineWidth = 3.5; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
    color(0x6D9A3A).setStroke(); chevron.stroke()

    centered("Then open Lanes from Applications. It asks for one permission.", top: 318, size: 13, weight: .regular, color: color(0x5D665F))

    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png"))
}
