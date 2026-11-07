import AppKit
import Foundation

// Local build-time asset generation. No external image services or paid tools.
// Render at 1024x1024; iOS applies the appropriate corner mask.
let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Bitmap context unavailable") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}
func line(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    path.lineWidth = width
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}
func circle(_ rect: CGRect, fill: NSColor) {
    let p = NSBezierPath(ovalIn: rect)
    fill.setFill()
    p.fill()
}

let background = NSBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size))
NSGradient(colors: [rgb(0.025, 0.035, 0.09), rgb(0.10, 0.08, 0.23), rgb(0.02, 0.25, 0.32)])!
    .draw(in: background, angle: -40)

let ambient = NSBezierPath(ovalIn: CGRect(x: 170, y: 100, width: 680, height: 760))
NSGradient(starting: rgb(0.22, 0.79, 0.91, 0.22), ending: rgb(0.1, 0.6, 0.92, 0.0))!
    .draw(in: ambient, relativeCenterPosition: NSPoint(x: 0, y: 0))

let frame = NSBezierPath(roundedRect: CGRect(x: 138, y: 146, width: 748, height: 732), xRadius: 172, yRadius: 172)
rgb(0.55, 0.83, 0.99, 0.15).setStroke()
frame.lineWidth = 8
frame.stroke()

// Book pages, drawn by hand as large shapes for legibility at home-screen size.
let left = NSBezierPath()
left.move(to: NSPoint(x: 504, y: 278))
left.curve(to: NSPoint(x: 217, y: 318),
           controlPoint1: NSPoint(x: 402, y: 334),
           controlPoint2: NSPoint(x: 316, y: 335))
left.line(to: NSPoint(x: 217, y: 666))
left.curve(to: NSPoint(x: 504, y: 629),
           controlPoint1: NSPoint(x: 328, y: 673),
           controlPoint2: NSPoint(x: 415, y: 650))
left.close()
rgb(0.19, 0.72, 0.89, 0.33).setFill()
left.fill()
line(left, color: rgb(0.33, 0.91, 0.99), width: 23)

let right = NSBezierPath()
right.move(to: NSPoint(x: 520, y: 278))
right.curve(to: NSPoint(x: 807, y: 318),
            controlPoint1: NSPoint(x: 624, y: 334),
            controlPoint2: NSPoint(x: 707, y: 335))
right.line(to: NSPoint(x: 807, y: 666))
right.curve(to: NSPoint(x: 520, y: 629),
            controlPoint1: NSPoint(x: 702, y: 674),
            controlPoint2: NSPoint(x: 607, y: 650))
right.close()
rgb(0.15, 0.49, 0.75, 0.42).setFill()
right.fill()
line(right, color: rgb(0.68, 0.97, 1.0), width: 23)

let base = NSBezierPath()
base.move(to: NSPoint(x: 197, y: 272))
base.curve(to: NSPoint(x: 506, y: 221),
           controlPoint1: NSPoint(x: 330, y: 256),
           controlPoint2: NSPoint(x: 448, y: 238))
base.curve(to: NSPoint(x: 830, y: 272),
           controlPoint1: NSPoint(x: 597, y: 243),
           controlPoint2: NSPoint(x: 718, y: 254))
line(base, color: rgb(0.40, 0.83, 0.93), width: 16)

let spine = NSBezierPath()
spine.move(to: NSPoint(x: 512, y: 263))
spine.line(to: NSPoint(x: 512, y: 640))
line(spine, color: rgb(0.87, 0.99, 1.0), width: 18)

// A little star above the book — the StarReader signature.
let cx: CGFloat = 706, cy: CGFloat = 783
let star = NSBezierPath()
for i in 0..<10 {
    let angle = CGFloat(i) * (.pi / 5) + .pi / 2
    let radius: CGFloat = i.isMultiple(of: 2) ? 66 : 26
    let point = NSPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
    if i == 0 { star.move(to: point) } else { star.line(to: point) }
}
star.close()
rgb(1.0, 0.88, 0.53).setFill()
star.fill()
circle(CGRect(x: 255, y: 752, width: 16, height: 16), fill: rgb(0.7, 0.96, 1.0))
circle(CGRect(x: 310, y: 798, width: 9, height: 9), fill: rgb(0.7, 0.96, 1.0))

ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let assetDir = URL(fileURLWithPath: "Sources/StarReaderNative/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try png.write(to: assetDir.appendingPathComponent("icon.png"), options: .atomic)
let contents = """
{
  "images": [
    {
      "filename": "icon.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
"""
try contents.write(to: assetDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Generated StarReader AppIcon (1024px)")
