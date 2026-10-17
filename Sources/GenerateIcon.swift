import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

func color(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rounded(_ rect: CGRect, _ radius: CGFloat, _ fill: NSColor, _ stroke: NSColor? = nil, _ line: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = line; path.stroke() }
}
func ellipse(_ rect: CGRect, _ fill: NSColor, _ stroke: NSColor? = nil, _ line: CGFloat = 1) {
    let path = NSBezierPath(ovalIn: rect)
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = line; path.stroke() }
}
func polygon(_ points: [CGPoint], _ fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close(); fill.setFill(); path.fill()
}

let bounds = CGRect(x: 28, y: 28, width: 968, height: 968)
let background = NSBezierPath(roundedRect: bounds, xRadius: 218, yRadius: 218)
let gradient = NSGradient(colors: [color(0x183C52), color(0x102636), color(0x0C1B2A)])!
gradient.draw(in: background, angle: -55)

// Soft accent behind the review card.
ellipse(CGRect(x: 640, y: 615, width: 250, height: 250), color(0x1E6370).withAlphaComponent(0.35))

// The image card.
rounded(CGRect(x: 195, y: 160, width: 635, height: 700), 60, color(0xF5F4EA))
rounded(CGRect(x: 235, y: 200, width: 555, height: 620), 34, color(0xE4E8DC))

// A warm, simple object in the image area.
polygon([CGPoint(x: 235, y: 390), CGPoint(x: 390, y: 545), CGPoint(x: 505, y: 440),
         CGPoint(x: 640, y: 570), CGPoint(x: 790, y: 420), CGPoint(x: 790, y: 234),
         CGPoint(x: 235, y: 234)], color(0xB7D3C7))
ellipse(CGRect(x: 575, y: 665, width: 105, height: 105), color(0xF1B86B))
rounded(CGRect(x: 422, y: 420, width: 250, height: 190), 76, color(0xE78A55))
ellipse(CGRect(x: 445, y: 560, width: 112, height: 112), color(0xE78A55))
ellipse(CGRect(x: 535, y: 560, width: 112, height: 112), color(0xE78A55))
ellipse(CGRect(x: 486, y: 510, width: 17, height: 17), color(0x293845))
ellipse(CGRect(x: 590, y: 510, width: 17, height: 17), color(0x293845))
ellipse(CGRect(x: 535, y: 463, width: 28, height: 19), color(0x293845))

// Detection box with oversized corner marks remains readable at Dock size.
let lime = color(0x7EDB9A)
let box = CGRect(x: 375, y: 375, width: 350, height: 350)
let outline = NSBezierPath(roundedRect: box, xRadius: 34, yRadius: 34)
outline.lineWidth = 15; lime.setStroke(); outline.stroke()
for rect in [CGRect(x: 359, y: 691, width: 48, height: 48),
             CGRect(x: 693, y: 691, width: 48, height: 48),
             CGRect(x: 359, y: 359, width: 48, height: 48),
             CGRect(x: 693, y: 359, width: 48, height: 48)] {
    rounded(rect, 15, color(0xF5F4EA))
    rounded(rect.insetBy(dx: 7, dy: 7), 10, lime)
}

// Small class tag anchors the icon to labeling work.
rounded(CGRect(x: 280, y: 105, width: 280, height: 92), 32, color(0x173247))
ellipse(CGRect(x: 309, y: 132, width: 36, height: 36), lime)
rounded(CGRect(x: 370, y: 136, width: 145, height: 18), 9, color(0xF5F4EA))
rounded(CGRect(x: 370, y: 163, width: 96, height: 12), 6, color(0x91A7A9))

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments[1]
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
