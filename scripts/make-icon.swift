import AppKit

// Reproducible vector artwork; all icon sizes are rendered directly, not upscaled.
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func render(_ pixels: Int, to name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
    NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.65, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.19, green: 0.24, blue: 0.78, alpha: 1))!.draw(in: tile, angle: -70)
    NSColor.white.withAlphaComponent(0.24).setStroke()
    tile.lineWidth = 3
    tile.stroke()
    // Match the menu-bar waveform, with a recognisable application tile.
    NSColor.white.setFill()
    for (index, height) in [116.0, 252.0, 400.0, 530.0, 340.0, 218.0, 116.0].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 238 + Double(index) * 82, y: 512 - height / 2,
                                       width: 56, height: height), xRadius: 28, yRadius: 28).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
for points in [16, 32, 128, 256, 512] {
    try render(points, to: "icon_\(points)x\(points).png")
    try render(points * 2, to: "icon_\(points)x\(points)@2x.png")
}
