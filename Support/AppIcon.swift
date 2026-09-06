import AppKit

// Renders the app icon set from the same TwenGlyph geometry the menu bar draws,
// so the two can never drift apart and no image files live in the repo. Apple's
// macOS icon grid: an 824/1024 rounded square (corner radius ≈ 22.4% of its
// side) in white, with the empty-eye mark in black at 50% of the square.
//
// Built by `make app`:  swiftc Support/AppIcon.swift Sources/TwenCore/TwenGlyph.swift
// Usage:                appicon <iconset directory>

@main
enum AppIcon {
    static func main() throws {
        let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try render(px: size * scale).write(to: outDir.appendingPathComponent(name))
            }
        }
    }
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    let canvas = CGFloat(px)
    let square = canvas * 824 / 1024
    let inset = (canvas - square) / 2
    let radius = square * 0.2237
    ctx.setFillColor(CGColor.white)
    ctx.addPath(CGPath(roundedRect: CGRect(x: inset, y: inset, width: square, height: square),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    // The glyph draws in a unit square with y down; flip it onto the centre.
    let mark = square * 0.5
    ctx.saveGState()
    ctx.translateBy(x: (canvas - mark) / 2, y: (canvas + mark) / 2)
    ctx.scaleBy(x: mark, y: -mark)
    TwenGlyph.draw(fillLineY: TwenGlyph.fillLineY(progress: 0), in: ctx)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
