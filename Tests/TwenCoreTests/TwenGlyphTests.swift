import CoreGraphics
import Testing
@testable import TwenCore

/// Renders the glyph at menu bar Retina size (36px) and samples alpha at points
/// chosen ≥1.5px from any edge, so antialiasing can't flip a verdict.
struct TwenGlyphTests {
    static let px = 36

    static func render(progress: Double, lid: Double = 1, iris: TwenGlyph.Iris = .dot) -> [UInt8] {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(px))
        ctx.scaleBy(x: CGFloat(px), y: -CGFloat(px))
        TwenGlyph.draw(fillLineY: TwenGlyph.fillLineY(progress: progress), lid: lid, iris: iris, in: ctx)
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

    @Test func closedLidIsASlitAndHidesTheIris() {
        let p = Self.render(progress: 1, lid: TwenGlyph.lidClosed)
        #expect(Self.alpha(p, 0.5, 0.5) > 200)        // slit is solid where the iris hole would be
        #expect(Self.alpha(p, 0.5, 0.40) < 30)        // lens interior above the slit is gone
        #expect(Self.alpha(p, 0.5, 0.60) < 30)
        #expect(Self.alpha(p, arm.0, arm.1) > 200)    // frame untouched
    }

    @Test func halfLidKeepsARoundIrisHole() {
        let p = Self.render(progress: 1, lid: 0.5)
        #expect(Self.alpha(p, 0.5, 0.5) < 30)         // iris hole
        #expect(Self.alpha(p, 0.5, 0.35) > 200)       // still inside the squeezed lens
        #expect(Self.alpha(p, 0.5, 0.20) < 30)        // outside it now
    }

    @Test func lidClosesMonotonically() {
        // Ink shrinks as the lid comes down while the iris hole is visible …
        var last = Int.max
        for lid in stride(from: 1.0, through: 0.3, by: -0.1) {
            let ink = Self.ink(Self.render(progress: 1, lid: lid))
            #expect(ink < last, "lid \(lid)")
            last = ink
        }
        // … and the closed slit, though solid, is still the least ink of all.
        #expect(Self.ink(Self.render(progress: 1, lid: TwenGlyph.lidClosed)) < last)
    }

    @Test func pauseIrisInvertsWithTheFill() {
        let bar = (0.43, 0.5), gap = (0.5, 0.5)
        let empty = Self.render(progress: 0, iris: .pause)
        #expect(Self.alpha(empty, bar.0, bar.1) > 200)   // solid bars
        #expect(Self.alpha(empty, gap.0, gap.1) < 30)
        let full = Self.render(progress: 1, iris: .pause)
        #expect(Self.alpha(full, bar.0, bar.1) < 30)     // bars become holes
        #expect(Self.alpha(full, gap.0, gap.1) > 200)
        let half = Self.render(progress: 0.5, iris: .pause)
        #expect(Self.alpha(half, bar.0, 0.44) > 200)     // above the line: ink
        #expect(Self.alpha(half, bar.0, 0.56) < 30)      // below the line: hole
    }

    @Test func noIrisLeavesTheLensPlain() {
        let p = Self.render(progress: 0, iris: .none)
        #expect(Self.alpha(p, 0.5, 0.5) < 30)
        #expect(Self.ink(Self.render(progress: 1, iris: .none)) > Self.ink(Self.render(progress: 1)))
    }

    @Test func fillLineSpansTheLensAndClamps() {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        #expect(close(TwenGlyph.fillLineY(progress: 0), TwenGlyph.lensBottom))
        #expect(close(TwenGlyph.fillLineY(progress: 1), TwenGlyph.lensTop))
        #expect(close(TwenGlyph.fillLineY(progress: -1), TwenGlyph.lensBottom))
        #expect(close(TwenGlyph.fillLineY(progress: 2), TwenGlyph.lensTop))
    }
}
