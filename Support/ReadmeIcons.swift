import AppKit

// Renders the menu bar states shown in the README from the same TwenGlyph
// geometry the status item draws, in a light- and a dark-mode ink so GitHub can
// swap them with <picture>. States with an arbitrary fill are shown half full.
// Every image sits on an 18pt-tall canvas like the status item, rendered at 4x.
//
// Built by `make readme-icons`:  swiftc Support/ReadmeIcons.swift Sources/TwenCore/TwenGlyph.swift
// Usage:                         readmeicons <output directory>

let scale: CGFloat = 4
let pointHeight: CGFloat = 18
// GitHub's default foreground colours for light and dark mode.
let inks: [(suffix: String, color: NSColor)] = [
    ("light", NSColor(srgbRed: 0x1f / 255.0, green: 0x23 / 255.0, blue: 0x28 / 255.0, alpha: 1)),
    ("dark", NSColor(srgbRed: 0xf0 / 255.0, green: 0xf6 / 255.0, blue: 0xfc / 255.0, alpha: 1)),
]

enum Icon {
    case eye(fill: Double, lid: Double = 1, iris: TwenGlyph.Iris = .dot)
    case countdown(String)
}

// Mirrors MenuBarController.eyeState for each phase.
let icons: [(name: String, icon: Icon)] = [
    ("working", .eye(fill: 0.5)),
    ("ramping", .eye(fill: 1, lid: 1 - 0.5 * (1 - TwenGlyph.lidClosed))),
    ("gray", .eye(fill: 1, lid: TwenGlyph.lidClosed)),
    ("countdown-xx", .countdown("XX")),
    ("satisfied", .eye(fill: 1, iris: .check)),  // accrued stays full until the next input
    ("paused", .eye(fill: 0.5, iris: .pause)),
    ("suppressed", .eye(fill: 0.5, iris: .stop)),
]

// The status item's countdown font and canvas width (see countdownImage).
let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
let countdownWidth: CGFloat = {
    let attributes: [NSAttributedString.Key: Any] = [.font: countdownFont]
    let digits = ("00" as NSString).size(withAttributes: attributes).width
    let roman = ("XX" as NSString).size(withAttributes: attributes).width
    return max(ceil(digits), ceil(roman), pointHeight)
}()

func render(_ icon: Icon, ink: NSColor) -> Data {
    let pointWidth: CGFloat
    if case .countdown = icon { pointWidth = countdownWidth } else { pointWidth = pointHeight }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(pointWidth * scale), pixelsHigh: Int(pointHeight * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pointWidth, height: pointHeight)
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let rect = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)

    switch icon {
    case let .eye(fill, lid, iris):
        // The glyph draws opaque black; tint it by compositing the ink over its alpha.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: pointHeight)
        ctx.scaleBy(x: pointHeight, y: -pointHeight)
        // Snap the fill line to a pixel row, as MenuBarIcon does.
        let rows = Double(pointHeight * scale)
        let line = (TwenGlyph.fillLineY(progress: fill) * rows).rounded() / rows
        TwenGlyph.draw(fillLineY: line, lid: lid, iris: iris, in: ctx)
        ctx.restoreGState()
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(ink.cgColor)
        ctx.fill(rect)
        ctx.endTransparencyLayer()
    case let .countdown(text):
        let attributes: [NSAttributedString.Key: Any] = [.font: countdownFont, .foregroundColor: ink]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (rect.width - size.width) / 2,
                                            y: (rect.height - size.height) / 2),
                                withAttributes: attributes)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

@main
enum ReadmeIcons {
    static func main() throws {
        let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for (name, icon) in icons {
            for (suffix, color) in inks {
                try render(icon, ink: color).write(to: outDir.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }
}
