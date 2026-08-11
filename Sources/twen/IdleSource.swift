import CoreGraphics
import Foundation

protocol IdleSource {
    /// Seconds since the last HID input event, system-wide. No permissions needed.
    var secondsSinceLastInput: TimeInterval { get }
}

struct SystemIdleSource: IdleSource {
    // kCGAnyInputEventType isn't exposed to Swift; ~0 is its raw value.
    private static let anyInput = CGEventType(rawValue: UInt32.max)

    var secondsSinceLastInput: TimeInterval {
        if let anyInput = Self.anyInput {
            return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        }
        // Fallback if the raw-value trick ever stops importing: min over common input types.
        let types: [CGEventType] = [
            .keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .scrollWheel, .leftMouseDragged, .rightMouseDragged,
        ]
        return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 0
    }
}
