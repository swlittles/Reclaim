import AppKit
let output = CommandLine.arguments[1]
let dev = CommandLine.arguments.contains("--development")
let folder = URL(fileURLWithPath: output).appendingPathComponent("Reclaim.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let s = CGFloat(size)
    let bounds = NSRect(x: s * 0.035, y: s * 0.035, width: s * 0.93, height: s * 0.93)
    let path = NSBezierPath(roundedRect: bounds, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(starting: NSColor(red: 0.1, green: 0.27, blue: 0.24, alpha: 1), ending: NSColor(red: 0.04, green: 0.13, blue: 0.15, alpha: 1))!.draw(in: path, angle: -45)
    let symbol = NSImage(systemSymbolName: "externaldrive.badge.checkmark", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(paletteColors: [NSColor(red: 0.56, green: 0.94, blue: 0.74, alpha: 1), .white]))!
    symbol.draw(in: NSRect(x: s * 0.19, y: s * 0.20, width: s * 0.64, height: s * 0.64))
    if dev && size >= 64 {
        let badge = NSRect(x: s * 0.27, y: s * 0.10, width: s * 0.46, height: s * 0.18)
        NSColor.systemOrange.setFill(); NSBezierPath(roundedRect: badge, xRadius: s * 0.05, yRadius: s * 0.05).fill()
        let text = "DEV" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.11, weight: .heavy), .foregroundColor: NSColor.black]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
}
