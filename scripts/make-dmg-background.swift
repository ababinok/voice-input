import AppKit

// Render both resolutions so dmgbuild can embed a Retina TIFF background.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 540 * scale,
                                  pixelsHigh: 300 * scale, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    (AffineTransform(scale: CGFloat(scale)) as NSAffineTransform).concat()
    NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 540, height: 300).fill()
    NSColor(srgbRed: 0.56, green: 0.59, blue: 0.65, alpha: 1).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 246, y: 165))
    arrow.line(to: NSPoint(x: 294, y: 165))
    arrow.move(to: NSPoint(x: 280, y: 179))
    arrow.line(to: NSPoint(x: 294, y: 165))
    arrow.line(to: NSPoint(x: 280, y: 151))
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
