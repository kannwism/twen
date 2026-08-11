import TwenCore

/// Applies engine effects to the actual displays. BackdropDesaturator is the real
/// backend; LoggingDesaturator narrates when the private API is unavailable.
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
