import AppKit
import TwenCore

/// The status item's eye icon: the twen mark with the lens filled in proportion
/// to the work interval consumed. Drawn as a template image from the analytic
/// glyph — no bitmaps to ship, crisp at every backing scale, tinted by the system.
@MainActor
enum MenuBarIcon {
    /// Canvas and glyph are both 18pt; the mark's 12-unit grid then lands on
    /// 1.5pt, i.e. whole device pixels at 2x.
    static let pointSize: CGFloat = 18

    /// Fill levels are quantised to lens rows at 2x (~30 for the whole interval),
    /// so the engine can publish every tick and the button only gets a new image
    /// when a row actually changes. Each level renders once and is cached.
    static let levels = Int(((TwenGlyph.lensBottom - TwenGlyph.lensTop) * pointSize * 2).rounded())
    private static var cache: [Int: NSImage] = [:]

    static func level(for progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * Double(levels)).rounded())
    }

    /// The eye filled to `progress` (0 = empty, 1 = full). Same level → same instance.
    static func eye(progress: Double) -> NSImage {
        let level = level(for: progress)
        if let cached = cache[level] { return cached }
        let fraction = Double(level) / Double(levels)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Snap the fill line to a device pixel row so it never smears grey.
            let scale = abs(ctx.userSpaceToDeviceSpaceTransform.d)
            let rows = Double(rect.height) * Double(scale)
            let line = (TwenGlyph.fillLineY(progress: fraction) * rows).rounded() / rows
            ctx.scaleBy(x: rect.width, y: rect.height)
            TwenGlyph.draw(fillLineY: line, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "twen"
        cache[level] = image
        return image
    }
}
