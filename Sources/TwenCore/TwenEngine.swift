import Foundation

public struct EngineConfig: Equatable, Sendable {
    public var workInterval: TimeInterval
    public var breakLength: TimeInterval
    public var rampDuration: TimeInterval
    public var idlePause: TimeInterval
    public var idleReset: TimeInterval
    /// Idle time while desaturated that counts the break as taken. Deliberately much
    /// shorter than idleReset: reading without input is still screen time (so the work
    /// timer shouldn't reset quickly), but a minute genuinely away rests the eyes.
    public var breakSatisfyIdle: TimeInterval
    public var satisfiedRestore: TimeInterval

    public init(
        workInterval: TimeInterval = 20 * 60,
        breakLength: TimeInterval = 20,
        rampDuration: TimeInterval = 2 * 60,
        idlePause: TimeInterval = 60,
        idleReset: TimeInterval = 3 * 60,
        breakSatisfyIdle: TimeInterval = 60,
        satisfiedRestore: TimeInterval = 5
    ) {
        self.workInterval = workInterval
        self.breakLength = breakLength
        self.rampDuration = rampDuration
        self.idlePause = idlePause
        self.idleReset = idleReset
        self.breakSatisfyIdle = breakSatisfyIdle
        self.satisfiedRestore = satisfiedRestore
    }

    /// Compressed timings for demos and end-to-end testing (TWEN_FAST=1).
    public static let fastDemo = EngineConfig(
        workInterval: 30,
        breakLength: 10,
        rampDuration: 10,
        idlePause: 10,
        idleReset: 20,
        breakSatisfyIdle: 10,
        satisfiedRestore: 3
    )
}

public enum TwenPhase: String, Equatable, Sendable {
    case waiting          // no accrual yet; timer starts on first real activity
    case working          // accruing during active input
    case paused           // idle past idlePause but under idleReset
    case ramping          // desaturation ramp in progress
    case gray             // fully desaturated, holding until a break
    case breakRunning     // break countdown; saturation ramping back
    case breakSatisfied   // idle >= breakSatisfyIdle while desaturated; awaiting next input
}

public enum EngineEvent: Equatable, Sendable {
    case tick(idle: TimeInterval, suppressed: Bool)
    case breakRequested
    case lockOrSleep      // screen lock, system sleep, fast-user-switch away
    case unlock           // unlock, wake, session became active
}

public enum EngineEffect: Equatable, Sendable {
    case ramp(toSaturation: Double, over: TimeInterval)
    case hold(atSaturation: Double)
}

/// Pure state machine for twen's 20-20-20 timer. All time arrives via `handle(_:at:)` —
/// no clocks, no timers, no AppKit — so every rule in the spec is deterministic under test.
public struct TwenEngine: Sendable {
    public private(set) var phase: TwenPhase = .waiting
    public private(set) var accrued: TimeInterval = 0
    /// 0 = full color, 1 = fully gray.
    public private(set) var rampProgress: Double = 0
    public private(set) var breakRemaining: TimeInterval = 0
    public let config: EngineConfig

    public var saturation: Double { 1 - rampProgress }

    private var lastTick: Date?
    private var lockedAt: Date?
    private var wasSuppressed = false

    public init(config: EngineConfig = EngineConfig()) {
        self.config = config
    }

    public mutating func handle(_ event: EngineEvent, at now: Date) -> [EngineEffect] {
        switch event {
        case let .tick(idle, suppressed): return tick(now: now, idle: idle, suppressed: suppressed)
        case .breakRequested: return startBreak()
        case .lockOrSleep: return locked(at: now)
        case .unlock: return unlocked(at: now)
        }
    }

    // MARK: - Tick

    private mutating func tick(now: Date, idle: TimeInterval, suppressed: Bool) -> [EngineEffect] {
        guard lockedAt == nil else { return [] } // lock/sleep owns time until unlock
        // Clamp dt so a missed stretch of ticks (coalesced timers, debugger) can't teleport the timer.
        let dt = min(max(lastTick.map { now.timeIntervalSince($0) } ?? 0, 0), 10)
        lastTick = now
        defer { wasSuppressed = suppressed }

        var effects: [EngineEffect] = []
        switch phase {
        case .waiting:
            if idle < config.idlePause { phase = .working }

        case .working:
            if idle >= config.idleReset {
                reset()
            } else if idle >= config.idlePause {
                phase = .paused
            } else {
                accrued += dt
                // Suppression blocks the ramp from *starting*; accrual continues,
                // so the ramp begins on the first unsuppressed tick past the threshold.
                if accrued >= config.workInterval, !suppressed {
                    phase = .ramping
                    effects.append(.ramp(toSaturation: 0, over: config.rampDuration))
                }
            }

        case .paused:
            if idle >= config.idleReset {
                reset()
            } else if idle < config.idlePause {
                phase = .working
            }

        case .ramping:
            if idle >= config.breakSatisfyIdle {
                phase = .breakSatisfied
                effects.append(.hold(atSaturation: saturation))
            } else if suppressed {
                if !wasSuppressed { effects.append(.hold(atSaturation: saturation)) }
            } else {
                if wasSuppressed {
                    effects.append(.ramp(toSaturation: 0, over: config.rampDuration * (1 - rampProgress)))
                }
                rampProgress = min(1, rampProgress + dt / config.rampDuration)
                if rampProgress >= 1 { phase = .gray }
            }

        case .gray:
            if idle >= config.breakSatisfyIdle { phase = .breakSatisfied }

        case .breakSatisfied:
            if idle < config.idlePause {
                // Their next input: the break already counted; give the color back.
                effects.append(.ramp(toSaturation: 1, over: config.satisfiedRestore))
                reset()
            }

        case .breakRunning:
            breakRemaining -= dt
            if breakRemaining <= 0 { reset() }
        }
        return effects
    }

    // MARK: - Discrete events

    private mutating func startBreak() -> [EngineEffect] {
        guard phase != .breakRunning else { return [] }
        phase = .breakRunning
        breakRemaining = config.breakLength
        let wasDesaturated = rampProgress > 0
        rampProgress = 0
        return wasDesaturated ? [.ramp(toSaturation: 1, over: config.breakLength)] : []
    }

    private mutating func locked(at now: Date) -> [EngineEffect] {
        guard lockedAt == nil else { return [] }
        lockedAt = now
        // Freeze any in-flight visual ramp: engine progress freezes with no ticks,
        // but Core Animation would otherwise keep animating to completion on its own.
        if phase == .ramping { return [.hold(atSaturation: saturation)] }
        return []
    }

    private mutating func unlocked(at now: Date) -> [EngineEffect] {
        guard let lockedAt else { return [] }
        let away = now.timeIntervalSince(lockedAt)
        self.lockedAt = nil
        lastTick = now

        switch phase {
        case .ramping, .gray:
            if away >= config.breakSatisfyIdle {
                // Break satisfied while away; the unlock itself is the "next input".
                reset()
                return [.ramp(toSaturation: 1, over: config.satisfiedRestore)]
            }
            if phase == .ramping {
                return [.ramp(toSaturation: 0, over: config.rampDuration * (1 - rampProgress))]
            }
            return []

        case .working:
            if away >= config.idleReset {
                reset()
            } else if away >= config.idlePause {
                phase = .paused
            }
            return []

        case .paused:
            if away >= config.idleReset { reset() }
            return []

        case .breakRunning:
            breakRemaining -= away
            if breakRemaining <= 0 { reset() }
            return []

        case .waiting, .breakSatisfied:
            return []
        }
    }

    private mutating func reset() {
        phase = .waiting
        accrued = 0
        rampProgress = 0
        breakRemaining = 0
    }
}
