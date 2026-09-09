import CoreGraphics
import Foundation

/// The twen mark: two stylised Xs (XX = 20 in Roman numerals) whose gap forms a
/// vertical eye. Fitted from logo/twen.svg — every outline in that file is an
/// exact circular arc, so the mark is a handful of circles in a unit square
/// (y down). Everything sits on a 12-unit grid: arm width, lens-to-arm gap and
/// iris radius are all 1/12, i.e. 1.5pt at the 18pt menu bar size.
///
/// The eye is the status display. Three independent controls:
/// - `fillLineY`: the lens (white of the eye) is filled from the bottom up to this
///   line. Above it the iris is solid ink; below it the iris is inverted into a
///   hole. One even-odd fill clipped to the lens does both.
/// - `lid`: squeezes the lens vertically about its centre, 1 = open, `lidClosed`
///   = a slit. The iris stays round and disappears once the lid no longer fits
///   around it, the way an eyelid covers a pupil.
/// - `iris`: a round pupil, a tiny pause sign (twen is paused), a hollow square
///   (twen is stopped by a suppression signal), or none.
public enum TwenGlyph {
    public enum Iris: Hashable, Sendable {
        case dot, pause, stop, none
    }

    /// Lens: intersection of two disks mirrored around x = 0.5.
    static let lensRadius = 0.6056
    static let lensCenterX = 0.0677
    /// Inner arm of each X: annulus around the *opposite* lens centre.
    static let armInnerRadius = 0.6889
    static let armOuterRadius = 0.7723
    /// Outer arm: annulus around a far-off centre; only its near edge falls
    /// inside the unit square, which is the clip that shapes each X.
    static let farCenterX = -1.4583
    static let farInnerRadius = 1.5417
    static let farOuterRadius = 1.6250
    static let irisRadius = 1.0 / 12.0
    /// Pause sign: two bars, each 1/18 wide with a 1/18 gap, 4/18 tall — the
    /// iris's footprint, slightly taller than wide so it reads as ⏸ not ▪▪.
    static let pauseBarWidth = 1.0 / 18.0
    static let pauseBarHeight = 4.0 / 18.0
    /// Stop sign: a hollow square on the same 18-grid as the pause bars — 4/18
    /// outside, 1/18 stroke — so both read at one weight. The even-odd fill
    /// inverts it below the fill line into a square hole with a solid centre.
    static let stopOuter = 4.0 / 18.0
    static let stopStroke = 1.0 / 18.0

    /// Where the two lens arcs meet at the top; the bottom tip is `1 - lensTop`.
    public static let lensTop: Double = {
        let dx = 0.5 - lensCenterX
        return 0.5 - (lensRadius * lensRadius - dx * dx).squareRoot()
    }()
    public static var lensBottom: Double { 1 - lensTop }

    /// Lid value for the closed eye: the lens becomes a slit exactly one grid
    /// unit (1/12) thick, the same weight as the arms.
    public static let lidClosed: Double = (1.0 / 12.0) / (lensBottom - lensTop)

    /// Unit-space y of the fill line for `progress` in 0...1 (0 = empty eye,
    /// 1 = lens completely filled). Callers may snap the result to device pixels.
    public static func fillLineY(progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return lensBottom - p * (lensBottom - lensTop)
    }

    /// Draws the mark in opaque black into `ctx`, whose CTM must map the unit
    /// square (y down) onto the target rect. Alpha is all that matters: the
    /// caller wraps the result in a template image.
    public static func draw(fillLineY: Double, lid: Double = 1, iris: Iris = .dot, in ctx: CGContext) {
        ctx.setFillColor(gray: 0, alpha: 1)

        // Each X is the union of two annuli, cut to the unit square.
        for mirrored in [false, true] {
            let mx: (Double) -> Double = { mirrored ? 1 - $0 : $0 }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: 1, height: 1))
            for (cx, inner, outer) in [
                (1 - lensCenterX, armInnerRadius, armOuterRadius),
                (farCenterX, farInnerRadius, farOuterRadius),
            ] {
                ctx.addEllipse(in: circle(mx(cx), 0.5, outer))
                ctx.addEllipse(in: circle(mx(cx), 0.5, inner))
                ctx.fillPath(using: .evenOdd)
            }
            ctx.restoreGState()
        }

        // Eye: clip to the (squeezed) lens, then one even-odd fill of "everything
        // below the line" plus the iris. Above the line the iris is the only ink;
        // below it the overlap cancels and the iris becomes a hole.
        let lid = min(max(lid, lidClosed), 1)
        var squeeze = CGAffineTransform(translationX: 0, y: 0.5)
            .scaledBy(x: 1, y: lid)
            .translatedBy(x: 0, y: -0.5)
        ctx.saveGState()
        ctx.addPath(CGPath(ellipseIn: circle(lensCenterX, 0.5, lensRadius), transform: &squeeze))
        ctx.clip()
        ctx.addPath(CGPath(ellipseIn: circle(1 - lensCenterX, 0.5, lensRadius), transform: &squeeze))
        ctx.clip()
        let line = min(max(fillLineY, lensTop), lensBottom)
        if line < lensBottom {
            ctx.addRect(CGRect(x: 0, y: line, width: 1, height: 1 - line))
        }
        let lensHeight = (lensBottom - lensTop) * lid
        switch iris {
        case .dot where lensHeight >= 2 * irisRadius * 1.15:
            ctx.addEllipse(in: circle(0.5, 0.5, irisRadius))
        case .pause where lensHeight >= pauseBarHeight * 1.15:
            let w = pauseBarWidth, h = pauseBarHeight
            ctx.addRect(CGRect(x: 0.5 - 1.5 * w, y: 0.5 - h / 2, width: w, height: h))
            ctx.addRect(CGRect(x: 0.5 + 0.5 * w, y: 0.5 - h / 2, width: w, height: h))
        case .stop where lensHeight >= stopOuter * 1.15:
            let outer = CGRect(x: 0.5 - stopOuter / 2, y: 0.5 - stopOuter / 2, width: stopOuter, height: stopOuter)
            ctx.addRect(outer)
            ctx.addRect(outer.insetBy(dx: stopStroke, dy: stopStroke))
        default:
            break // lid too far down to show a pupil, or none requested
        }
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> CGRect {
        CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
    }
}
