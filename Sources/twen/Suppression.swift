protocol SuppressionChecking {
    /// True when desaturation must not start or advance (video, presentation, screen share…).
    /// Phase 3 implements the real signals: power assertions, fullscreen, camera, recording.
    var isSuppressed: Bool { get }
}

struct NoSuppression: SuppressionChecking {
    var isSuppressed: Bool { false }
}
