import AppKit
import Foundation
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 208, yRadius: 208).fill()
    let tiles: [(NSRect, NSColor)] = [
        (NSRect(x: 190, y: 224, width: 160, height: 576), NSColor(red: 0.75, green: 0.88, blue: 0.58, alpha: 1)),
        (NSRect(x: 374, y: 224, width: 130, height: 576), NSColor(red: 0.63, green: 0.73, blue: 0.94, alpha: 1)),
        (NSRect(x: 528, y: 542, width: 306, height: 258), NSColor(red: 0.91, green: 0.68, blue: 0.49, alpha: 1)),
        (NSRect(x: 528, y: 224, width: 142, height: 294), NSColor(red: 0.72, green: 0.65, blue: 0.85, alpha: 1)),
        (NSRect(x: 694, y: 224, width: 140, height: 294), NSColor(red: 0.52, green: 0.79, blue: 0.77, alpha: 1))
    ]
    for (rect, color) in tiles { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill() }
    NSGraphicsContext.restoreGraphicsState()
    let names: [Int: [String]] = [16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"], 64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"], 256: ["icon_128x128@2x.png", "icon_256x256.png"], 512: ["icon_256x256@2x.png", "icon_512x512.png"], 1024: ["icon_512x512@2x.png"]]
    for name in names[size]! { try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name)) }
}
