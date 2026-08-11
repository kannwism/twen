import TwenCore

/// Applies engine effects to the actual displays. Phase 2 adds BackdropDesaturator
/// (the CABackdropLayer backend proven in spike/a-backdrop); until then we just narrate.
@MainActor
protocol Desaturating {
    func apply(_ effect: EngineEffect)
}

@MainActor
final class LoggingDesaturator: Desaturating {
    func apply(_ effect: EngineEffect) {
        switch effect {
        case let .ramp(toSaturation, over):
            print("desaturator: ramp to saturation \(toSaturation) over \(over)s")
        case let .hold(atSaturation):
            print("desaturator: hold at saturation \(atSaturation)")
        }
    }
}
