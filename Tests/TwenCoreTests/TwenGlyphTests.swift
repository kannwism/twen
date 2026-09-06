import CoreGraphics
import Testing
@testable import TwenCore

/// Renders the glyph at menu bar Retina size (36px) and samples alpha at points
/// chosen ≥1.5px from any edge, so antialiasing can't flip a verdict.
struct TwenGlyphTests {
    static let px = 36

    static func render(progress: Double) -> [UInt8] {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(px))
        ctx.scaleBy(x: CGFloat(px), y: -CGFloat(px))
        TwenGlyph.draw(fillLineY: TwenGlyph.fillLineY(progress: progress), in: ctx)
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // Keep only the alpha byte of each RGBA pixel.
        return (0..<(px * px)).map { data[$0 * 4 + 3] }
    }

    /// Alpha at unit-square coordinates (y down).
    static func alpha(_ pixels: [UInt8], _ x: Double, _ y: Double) -> UInt8 {
        pixels[Int(y * Double(px)) * px + Int(x * Double(px))]
    }

    static func ink(_ pixels: [UInt8]) -> Int { pixels.reduce(0) { $0 + Int($1) } }

    let iris = (0.5, 0.5)
    let lensLow = (0.5, 0.85)      // inside the lens, below centre
    let lensHigh = (0.5, 0.15)     // inside the lens, above centre
    let arm = (0.16, 0.5)          // where the left X's two arms cross
    let gap = (0.285, 0.5)         // between the inner arm and the lens edge
    let aboveLens = (0.5, 0.03)    // between the X tips, above the lens

    @Test func emptyEyeShowsOnlyTheIris() {
        let p = Self.render(progress: 0)
        #expect(Self.alpha(p, iris.0, iris.1) > 200)
        #expect(Self.alpha(p, lensLow.0, lensLow.1) < 30)
        #expect(Self.alpha(p, lensHigh.0, lensHigh.1) < 30)
    }

    @Test func fullEyeInvertsTheIris() {
        let p = Self.render(progress: 1)
        #expect(Self.alpha(p, iris.0, iris.1) < 30)
        #expect(Self.alpha(p, lensLow.0, lensLow.1) > 200)
        #expect(Self.alpha(p, lensHigh.0, lensHigh.1) > 200)
    }

    @Test func halfFillsFromTheBottom() {
        let p = Self.render(progress: 0.5)
        #expect(Self.alpha(p, lensLow.0, lensLow.1) > 200)
        #expect(Self.alpha(p, lensHigh.0, lensHigh.1) < 30)
    }

    @Test func frameIsIndependentOfProgress() {
        for progress in [0.0, 0.3, 0.5, 0.7, 1.0] {
            let p = Self.render(progress: progress)
            #expect(Self.alpha(p, arm.0, arm.1) > 200, "arm at \(progress)")
            #expect(Self.alpha(p, 1 - arm.0, arm.1) > 200, "mirrored arm at \(progress)")
            #expect(Self.alpha(p, gap.0, gap.1) < 30, "gap at \(progress)")
            #expect(Self.alpha(p, aboveLens.0, aboveLens.1) < 30, "above lens at \(progress)")
        }
    }

    @Test func inkGrowsMonotonicallyWithProgress() {
        var last = -1
        for step in 0...10 {
            let ink = Self.ink(Self.render(progress: Double(step) / 10))
            #expect(ink > last, "step \(step)")
            last = ink
        }
    }

    @Test func fillLineSpansTheLensAndClamps() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        #expect(close(TwenGlyph.fillLineY(progress: 0), TwenGlyph.lensBottom))
        #expect(close(TwenGlyph.fillLineY(progress: 1), TwenGlyph.lensTop))
        #expect(close(TwenGlyph.fillLineY(progress: -1), TwenGlyph.lensBottom))
        #expect(close(TwenGlyph.fillLineY(progress: 2), TwenGlyph.lensTop))
    }
}
