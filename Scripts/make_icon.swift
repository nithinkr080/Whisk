import AppKit

// Renders the Whisk app icon into an .iconset folder: swift make_icon.swift <out.iconset>
func png(size s: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let f = CGFloat(s)
    let bg = NSRect(x: f * 0.05, y: f * 0.05, width: f * 0.9, height: f * 0.9)
    let path = NSBezierPath(roundedRect: bg, xRadius: f * 0.2, yRadius: f * 0.2)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 0.98, alpha: 1), NSColor(red: 0.45, green: 0.25, blue: 0.85, alpha: 1)])!
        .draw(in: path, angle: -60)

    func window(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, alpha: CGFloat) {
        let r = NSRect(x: f * x, y: f * y, width: f * w, height: f * h)
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: f * 0.04, yRadius: f * 0.04).fill()
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.maxY - f * 0.07, width: r.width, height: f * 0.07),
                     xRadius: f * 0.04, yRadius: f * 0.04).fill()
    }
    window(0.16, 0.30, 0.34, 0.34, alpha: 0.45)
    window(0.50, 0.30, 0.34, 0.34, alpha: 0.45)
    window(0.27, 0.22, 0.46, 0.46, alpha: 0.95)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
