import AppKit
import Foundation

// Lorc's Poker Hand icon (CC BY 3.0). See App/IconSources/ATTRIBUTION.txt.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard let artwork = NSImage(contentsOf: root.appendingPathComponent("App/IconSources/poker-hand.png")) else {
    throw CocoaError(.fileReadCorruptFile)
}
func render(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.035, green: 0.20, blue: 0.17, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 220, yRadius: 220).fill()
    artwork.draw(in: NSRect(x: 112, y: 112, width: 800, height: 800), from: .zero,
                 operation: .sourceOver, fraction: 1, respectFlipped: false,
                 hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return data
}
let preview = try render(pixels: 1024)
try preview.write(to: root.appendingPathComponent("App/icon-1024.png"))
try preview.write(to: root.appendingPathComponent("Sources/FreeCellApp/Resources/AppIcon.png"))
let attribution = try Data(contentsOf: root.appendingPathComponent("App/IconSources/ATTRIBUTION.txt"))
try attribution.write(to: root.appendingPathComponent("Sources/FreeCellApp/Resources/Icon-Attribution.txt"))
let iconset = root.appendingPathComponent("build/FreeCell.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("App/FreeCell.icns").path]
try converter.run(); converter.waitUntilExit()
guard converter.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
