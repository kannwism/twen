import AppKit
import Carbon.HIToolbox
import TwenCore

/// UserDefaults-backed settings. Timing values are persisted on every change and
/// pushed to the running engine live via `AppModel.apply(config:)` — the engine
/// picks the new config up on its next tick.
///
/// Sanity constraints, enforced by clamping on write (and on load, so hand-edited
/// defaults can't produce a nonsensical engine):
/// - workInterval: 5–90 min
/// - breakLength: 10–120 s
/// - rampDuration: 10 s – 10 min
/// - idlePause: 20 s – 10 min
/// - idleReset: ≥ idlePause + 30 s
/// - breakSatisfyIdle: 20 s – idleReset
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let workIntervalRange: ClosedRange<TimeInterval> = (5 * 60)...(90 * 60)
    static let breakLengthRange: ClosedRange<TimeInterval> = 10...120
    static let rampDurationRange: ClosedRange<TimeInterval> = 10...(10 * 60)
    static let idlePauseRange: ClosedRange<TimeInterval> = 20...(10 * 60)
    /// idleReset must exceed idlePause by at least this much.
    static let idleResetMargin: TimeInterval = 30
    /// UI ceiling for idleReset; the store itself only enforces the lower bound.
    static let idleResetDisplayMax: TimeInterval = 30 * 60
    static let breakSatisfyIdleMinimum: TimeInterval = 20

    private let defaults: UserDefaults

    // MARK: - Timing (all seconds)

    @Published var workInterval: TimeInterval {
        didSet {
            workInterval = Self.clamp(workInterval, to: Self.workIntervalRange)
            timingChanged("workInterval", workInterval)
        }
    }

    @Published var breakLength: TimeInterval {
        didSet {
            breakLength = Self.clamp(breakLength, to: Self.breakLengthRange)
            timingChanged("breakLength", breakLength)
        }
    }

    @Published var rampDuration: TimeInterval {
        didSet {
            rampDuration = Self.clamp(rampDuration, to: Self.rampDurationRange)
            timingChanged("rampDuration", rampDuration)
        }
    }

    @Published var idlePause: TimeInterval {
        didSet {
            idlePause = Self.clamp(idlePause, to: Self.idlePauseRange)
            timingChanged("idlePause", idlePause)
            // Cascades through idleReset's own didSet, which persists and re-applies.
            if idleReset < idlePause + Self.idleResetMargin {
                idleReset = idlePause + Self.idleResetMargin
            }
        }
    }

    @Published var idleReset: TimeInterval {
        didSet {
            idleReset = max(idleReset, idlePause + Self.idleResetMargin)
            timingChanged("idleReset", idleReset)
            if breakSatisfyIdle > idleReset { breakSatisfyIdle = idleReset }
        }
    }

    @Published var breakSatisfyIdle: TimeInterval {
        didSet {
            breakSatisfyIdle = Self.clamp(breakSatisfyIdle, to: Self.breakSatisfyIdleMinimum...idleReset)
            timingChanged("breakSatisfyIdle", breakSatisfyIdle)
        }
    }

    /// Engine config assembled from the stored timing values (satisfiedRestore
    /// keeps its built-in default; it isn't user-facing).
    var engineConfig: EngineConfig {
        EngineConfig(
            workInterval: workInterval,
            breakLength: breakLength,
            rampDuration: rampDuration,
            idlePause: idlePause,
            idleReset: idleReset,
            breakSatisfyIdle: breakSatisfyIdle
        )
    }

    // MARK: - Hotkey (Carbon virtual keycode + modifier flags)

    @Published private(set) var hotkeyKeyCode: Int
    @Published private(set) var hotkeyModifiers: Int

    /// Human-readable current combo, e.g. "⌥⌘B".
    var comboDescription: String {
        HotkeyManager.describe(keyCode: UInt32(hotkeyKeyCode), modifiers: UInt32(hotkeyModifiers))
    }

    /// Persists both hotkey keys, then re-registers the global shortcut so the
    /// change is live immediately.
    func setHotkey(keyCode: Int, modifiers: Int) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        defaults.set(keyCode, forKey: "hotkeyKeyCode")
        defaults.set(modifiers, forKey: "hotkeyModifiers")
        AppModel.shared.hotkey.reRegister()
    }

    // MARK: - General

    /// Only the preference lives here; the pause-on-battery behavior reads this key.
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: "pauseOnBattery") }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = EngineConfig()
        func stored(_ key: String, or fallbackValue: TimeInterval) -> TimeInterval {
            defaults.object(forKey: key) as? TimeInterval ?? fallbackValue
        }
        workInterval = Self.clamp(stored("workInterval", or: fallback.workInterval), to: Self.workIntervalRange)
        breakLength = Self.clamp(stored("breakLength", or: fallback.breakLength), to: Self.breakLengthRange)
        rampDuration = Self.clamp(stored("rampDuration", or: fallback.rampDuration), to: Self.rampDurationRange)
        let pause = Self.clamp(stored("idlePause", or: fallback.idlePause), to: Self.idlePauseRange)
        idlePause = pause
        let reset = max(stored("idleReset", or: fallback.idleReset), pause + Self.idleResetMargin)
        idleReset = reset
        breakSatisfyIdle = Self.clamp(
            stored("breakSatisfyIdle", or: fallback.breakSatisfyIdle),
            to: Self.breakSatisfyIdleMinimum...reset
        )
        hotkeyKeyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_B
        hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? (cmdKey | optionKey)
        pauseOnBattery = defaults.bool(forKey: "pauseOnBattery")
    }

    // MARK: - Plumbing

    private func timingChanged(_ key: String, _ value: TimeInterval) {
        defaults.set(value, forKey: key)
        AppModel.shared.apply(config: engineConfig)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
