import AppKit
import Foundation

// User-selected icon #2 (glassmorphism) is stored in Git.
// Recreate 1024px iOS AppIcon from the same art on every build.
let source = URL(fileURLWithPath: "Art/StarReader-Glass-Icon.jpg")
guard let image = NSImage(contentsOf: source) else {
    fatalError("StarReader selected icon source missing")
}
let size = 1024
guard let rep = NSBitmapImageRep(
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
) else {
    fatalError("Unable to create icon bitmap")
}
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Unable to create icon graphics context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
image.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .copy,
    fraction: 1.0
)
ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let assetDir = URL(
    fileURLWithPath: "Sources/StarReaderNative/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)
try FileManager.default.createDirectory(
    at: assetDir, withIntermediateDirectories: true
)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode selected AppIcon")
}
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
try contents.write(
    to: assetDir.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
print("Generated selected StarReader glass AppIcon (1024px)")
