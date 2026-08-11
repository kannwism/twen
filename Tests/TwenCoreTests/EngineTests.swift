import Foundation
import Testing
@testable import TwenCore

/// Deterministic simulation harness: a marching clock, ticks every 2s.
/// Scaled config keeps tests readable: 100s work interval, 20s ramp, 10s break.
private struct Sim {
    var engine: TwenEngine
    var now = Date(timeIntervalSinceReferenceDate: 0)
    var idle: TimeInterval = 9999 // launch state: no input seen yet
    var lastEffects: [EngineEffect] = []
    var collected: [EngineEffect] = []

    init(_ config: EngineConfig = EngineConfig(
        workInterval: 100, breakLength: 10, rampDuration: 20,
        idlePause: 20, idleReset: 60, satisfiedRestore: 5
    )) {
        engine = TwenEngine(config: config)
    }

    mutating func tick(idle: TimeInterval? = nil, suppressed: Bool = false, advance: TimeInterval = 2) {
        now += advance
        if let idle { self.idle = idle }
        lastEffects = engine.handle(.tick(idle: self.idle, suppressed: suppressed), at: now)
        collected += lastEffects
    }

    /// Active input for `duration` seconds (idle stays ~1s).
    mutating func work(_ duration: TimeInterval, suppressed: Bool = false) {
        for _ in 0..<Int(duration / 2) { tick(idle: 1, suppressed: suppressed) }
    }

    /// Hands-off time; the idle counter grows tick by tick.
    /// `startingAt` jumps past the initial stretch (idle < idlePause still accrues as work).
    mutating func goIdle(_ duration: TimeInterval, startingAt: TimeInterval = 0) {
        var i = startingAt
        for _ in 0..<Int(duration / 2) {
            i += 2
            tick(idle: i)
        }
    }

    /// Time passing with no ticks at all (locked / asleep).
    mutating func wait(_ seconds: TimeInterval) { now += seconds }

    mutating func send(_ event: EngineEvent) {
        lastEffects = engine.handle(event, at: now)
        collected += lastEffects
    }

    /// Drive to the ramping phase: accrue past the work interval.
    mutating func workToRamp() {
        work(110)
        precondition(engine.phase == .ramping, "expected ramping, got \(engine.phase)")
    }

    /// Drive all the way to full gray.
    mutating func workToGray() {
        workToRamp()
        work(24) // ramp duration is 20s
        precondition(engine.phase == .gray, "expected gray, got \(engine.phase)")
    }
}

// MARK: - Accrual

@Test func timerStartsOnFirstActivityNotLaunch() {
    var sim = Sim()
    sim.tick(idle: 500)
    sim.tick(idle: 502)
    #expect(sim.engine.phase == .waiting)
    #expect(sim.engine.accrued == 0)
    sim.tick(idle: 1)
    #expect(sim.engine.phase == .working)
}

@Test func accruesOnlyDuringActiveInput() {
    var sim = Sim()
    sim.work(20)
    #expect(sim.engine.phase == .working)
    #expect(sim.engine.accrued > 14 && sim.engine.accrued <= 20)
}

@Test func shortIdlePausesAndResumeKeepsAccrued() {
    var sim = Sim()
    sim.work(30)
    let before = sim.engine.accrued
    sim.goIdle(38, startingAt: 20) // past idlePause (20s), under idleReset (60s)
    #expect(sim.engine.phase == .paused)
    #expect(sim.engine.accrued == before)
    sim.work(4)
    #expect(sim.engine.phase == .working)
    #expect(sim.engine.accrued > before)
}

@Test func longIdleResets() {
    var sim = Sim()
    sim.work(30)
    sim.goIdle(70) // past idleReset (60s)
    #expect(sim.engine.phase == .waiting)
    #expect(sim.engine.accrued == 0)
}

// MARK: - Ramp

@Test func rampStartsAtWorkInterval() {
    var sim = Sim()
    sim.workToRamp()
    #expect(sim.collected.contains(.ramp(toSaturation: 0, over: 20)))
}

@Test func rampCompletesToGray() {
    var sim = Sim()
    sim.workToGray()
    #expect(sim.engine.rampProgress == 1)
    #expect(sim.engine.saturation == 0)
}

@Test func suppressionBlocksRampStart() {
    var sim = Sim()
    sim.work(110, suppressed: true)
    #expect(sim.engine.phase == .working) // past threshold but suppressed
    #expect(sim.engine.accrued > 100)
    sim.work(4, suppressed: false)
    #expect(sim.engine.phase == .ramping)
}

@Test func suppressionPausesRampThenResumesWithRemainingDuration() {
    var sim = Sim()
    sim.workToRamp()
    sim.work(8) // partway through the 20s ramp
    let progress = sim.engine.rampProgress
    #expect(progress > 0 && progress < 1)

    sim.work(10, suppressed: true)
    #expect(sim.engine.rampProgress == progress) // frozen
    #expect(sim.collected.contains(.hold(atSaturation: 1 - progress)))

    sim.collected = []
    sim.work(2, suppressed: false)
    guard case let .ramp(to, over)? = sim.collected.first else {
        Issue.record("expected resume ramp effect")
        return
    }
    #expect(to == 0)
    #expect(abs(over - 20 * (1 - progress)) < 0.001)
}

// MARK: - Breaks

@Test func idleWhileDesaturatedSatisfiesBreakAndColorReturnsOnInput() {
    var sim = Sim()
    sim.workToRamp()
    sim.work(8)
    sim.goIdle(62)
    #expect(sim.engine.phase == .breakSatisfied)

    sim.collected = []
    sim.tick(idle: 1) // user is back
    #expect(sim.collected.contains(.ramp(toSaturation: 1, over: 5)))
    #expect(sim.engine.phase == .waiting)
    #expect(sim.engine.accrued == 0)
}

@Test func manualBreakRestoresColorAndResets() {
    var sim = Sim()
    sim.workToGray()
    sim.send(.breakRequested)
    #expect(sim.engine.phase == .breakRunning)
    #expect(sim.lastEffects.contains(.ramp(toSaturation: 1, over: 10)))

    sim.goIdle(14, startingAt: 30) // user looking away; countdown runs regardless of idle
    #expect(sim.engine.phase == .waiting)
    #expect(sim.engine.accrued == 0)
}

@Test func earlyBreakBeforeDesaturationJustRunsCountdown() {
    var sim = Sim()
    sim.work(30)
    sim.send(.breakRequested)
    #expect(sim.engine.phase == .breakRunning)
    #expect(sim.lastEffects.isEmpty) // already at full color, nothing to restore
    sim.work(14) // user keeps typing straight through the countdown
    #expect(sim.engine.phase == .working) // break ended, timer restarted from ~zero
    #expect(sim.engine.accrued <= 4)
}

// MARK: - Lock / sleep

@Test func shortLockPausesLongLockResets() {
    var sim = Sim()
    sim.work(30)
    let before = sim.engine.accrued

    sim.send(.lockOrSleep)
    sim.wait(30)
    sim.send(.unlock)
    #expect(sim.engine.phase == .paused)
    #expect(sim.engine.accrued == before)

    sim.work(4)
    sim.send(.lockOrSleep)
    sim.wait(70)
    sim.send(.unlock)
    #expect(sim.engine.phase == .waiting)
    #expect(sim.engine.accrued == 0)
}

@Test func ticksWhileLockedAreIgnored() {
    var sim = Sim()
    sim.work(30)
    let before = sim.engine.accrued
    sim.send(.lockOrSleep)
    sim.work(20) // e.g. unlock-screen keystrokes producing low idle readings
    #expect(sim.engine.accrued == before)
    #expect(sim.engine.phase == .working) // unchanged until unlock adjudicates
}

@Test func lockWhileDesaturatedSatisfiesBreakOnLongAbsence() {
    var sim = Sim()
    sim.workToGray()
    sim.send(.lockOrSleep)
    sim.wait(70)
    sim.send(.unlock)
    #expect(sim.lastEffects.contains(.ramp(toSaturation: 1, over: 5)))
    #expect(sim.engine.phase == .waiting)
}

@Test func lockMidRampHoldsThenShortUnlockResumes() {
    var sim = Sim()
    sim.workToRamp()
    sim.work(8)
    let progress = sim.engine.rampProgress

    sim.send(.lockOrSleep)
    #expect(sim.lastEffects.contains(.hold(atSaturation: 1 - progress)))

    sim.wait(30) // under idleReset: pause only, ramp resumes
    sim.send(.unlock)
    guard case let .ramp(to, over)? = sim.lastEffects.first else {
        Issue.record("expected resume ramp effect")
        return
    }
    #expect(to == 0)
    #expect(abs(over - 20 * (1 - progress)) < 0.001)
    #expect(sim.engine.phase == .ramping)
}
