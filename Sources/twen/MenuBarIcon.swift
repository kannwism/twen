import AppKit
import TwenCore

/// What the eye shows: how full the lens is, how far the lid is down, and what
/// sits in the iris. Pure data so the controller can map engine phases to it
/// and the icon cache can key on it.
struct EyeState: Hashable {
    var fill: Double          // 0 empty … 1 full
    var lid: Double = 1       // 1 open … TwenGlyph.lidClosed
    var iris: TwenGlyph.Iris = .dot
}

/// The status item's eye icon, drawn as a template image from the analytic
/// glyph — no bitmaps to ship, crisp at every backing scale, tinted by the system.
@MainActor
enum MenuBarIcon {
    /// Canvas and glyph are both 18pt; the mark's 12-unit grid then lands on
    /// 1.5pt, i.e. whole device pixels at 2x.
    static let pointSize: CGFloat = 18

    /// Rows of the open lens at 2x. Fill and lid are both quantised to this, so
    /// the engine can publish every tick and the button only gets a new image
    /// when a row actually changes (~30 fill steps per interval, ~28 lid steps
    /// per ramp). Each distinct state renders once and is cached.
    static let rows = Int(((TwenGlyph.lensBottom - TwenGlyph.lensTop) * pointSize * 2).rounded())

    struct Key: Hashable {
        var fillRows: Int
        var lidRows: Int
        var iris: TwenGlyph.Iris
    }
    private static var cache: [Key: NSImage] = [:]

    static func key(for state: EyeState) -> Key {
        let fill = min(max(state.fill, 0), 1)
        let lid = min(max(state.lid, TwenGlyph.lidClosed), 1)
        return Key(fillRows: Int((fill * Double(rows)).rounded()),
                   lidRows: Int((lid * Double(rows)).rounded()),
                   iris: state.iris)
    }

    /// The eye for `state`. Same quantised key → same instance.
    static func image(for state: EyeState) -> NSImage {
        let key = key(for: state)
        if let cached = cache[key] { return cached }
        let fill = Double(key.fillRows) / Double(rows)
        let lid = max(TwenGlyph.lidClosed, Double(key.lidRows) / Double(rows))
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Snap the fill line to a device pixel row so it never smears grey.
            let scale = abs(ctx.userSpaceToDeviceSpaceTransform.d)
            let deviceRows = Double(rect.height) * Double(scale)
            let line = (TwenGlyph.fillLineY(progress: fill) * deviceRows).rounded() / deviceRows
            ctx.scaleBy(x: rect.width, y: rect.height)
            TwenGlyph.draw(fillLineY: line, lid: lid, iris: key.iris, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "twen"
        cache[key] = image
        return image
    }
}
