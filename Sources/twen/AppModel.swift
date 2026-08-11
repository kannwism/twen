import AppKit
import IOKit.ps
import TwenCore

/// Why twen is currently paused — drives the popover's status line.
enum PauseReason: Equatable {
    case manual(until: Date?)
    case battery
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var engine: TwenEngine
    @Published private(set) var isSuppressed = false
    /// Estimated wall-clock end of the running break. The engine only ticks every
    /// 2s, so `breakRemaining` moves in jumps; the popover derives a smooth 1s
    /// countdown from this date instead. Nil outside `.breakRunning`.
    @Published private(set) var breakEndEstimate: Date?
    /// Non-nil exactly while the engine is snoozed; cleared on resume, expiry,
    /// or anything else that moves the engine out of `.snoozed`.
    @Published private(set) var pauseReason: PauseReason?
    /// Concrete suppression details for the popover, e.g. ["power-assertion: zoom.us"].
    /// Empty when not suppressed or when the checker can't itemize its signals.
    @Published private(set) var suppressionSignals: [String] = []

    /// Owned here (not by AppDelegate) so the settings UI can unregister/re-register
    /// the shortcut live. Callback behavior is unchanged: pressed → requestBreak().
    let hotkey = HotkeyManager()

    private let idleSource: any IdleSource
    private let suppression: any SuppressionChecking
    private let desaturator: any Desaturating
    private var pollTask: Task<Void, Never>?
    private var wasOnBattery = false

    init(
        idleSource: any IdleSource = SystemIdleSource(),
        suppression: any SuppressionChecking = SuppressionMonitor(),
        desaturator: (any Desaturating)? = nil
    ) {
        self.idleSource = idleSource
        self.suppression = suppression
        if let desaturator {
            self.desaturator = desaturator
        } else if BackdropDesaturator.isSupported {
            self.desaturator = BackdropDesaturator()
        } else {
            // The private API vanished (future macOS?): stay functional, just invisible.
            // A public-API overlay fallback backend is planned as a Phase 3 leaf.
            print("twen: CABackdropLayer unavailable; falling back to logging only (no visual effect)")
            self.desaturator = LoggingDesaturator()
        }
        let fast = ProcessInfo.processInfo.environment["TWEN_FAST"] == "1"
        engine = TwenEngine(config: fast ? .fastDemo : SettingsStore.shared.engineConfig)
        if fast { print("twen: TWEN_FAST demo timings active") }
    }

    func start() {
        guard pollTask == nil else { return }
        print("twen: started, phase=\(engine.phase.rawValue)")

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.tick()
            }
        }

        observeDistributed("com.apple.screenIsLocked") { [weak self] in self?.send(.lockOrSleep) }
        observeDistributed("com.apple.screenIsUnlocked") { [weak self] in self?.send(.unlock) }
        observeWorkspace(NSWorkspace.willSleepNotification) { [weak self] in self?.send(.lockOrSleep) }
        observeWorkspace(NSWorkspace.didWakeNotification) { [weak self] in self?.send(.unlock) }
        observeWorkspace(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.send(.lockOrSleep) }
        observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.send(.unlock) }
    }

    func requestBreak() { send(.breakRequested) }

    /// Live-applies a settings change; the engine picks it up on its next tick.
    func apply(config: EngineConfig) {
        engine.config = config
        print("twen: config updated")
    }

    // MARK: - Pause / resume

    func pause(for duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        pauseReason = .manual(until: until)
        send(.snoozeRequested(until: until))
    }

    /// "Tomorrow" means the next 4 AM, not midnight, so a pause taken during a
    /// late-night session doesn't spring back an hour later.
    func pauseUntilTomorrow() {
        guard let until = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 4, minute: 0), matchingPolicy: .nextTime
        ) else { return }
        pauseReason = .manual(until: until)
        send(.snoozeRequested(until: until))
    }

    func resume() {
        pauseReason = nil
        send(.snoozeCancelled)
    }

    private func tick() {
        checkBattery()
        let suppressed = suppression.isSuppressed
        if suppressed != isSuppressed { isSuppressed = suppressed }
        let signals = suppressed ? (suppression as? SuppressionMonitor)?.activeSignals() ?? [] : []
        if signals != suppressionSignals { suppressionSignals = signals }
        send(.tick(idle: idleSource.secondsSinceLastInput, suppressed: suppressed))
    }

    /// Battery-conditional pause (Settings toggle; we only read the key). Snoozing
    /// fires on the AC->battery *transition*, so a manual resume while still on
    /// battery sticks; the cancel fires on state (back on AC while battery-paused).
    /// Manual pauses are never auto-cancelled by returning to AC.
    private func checkBattery() {
        guard UserDefaults.standard.bool(forKey: "pauseOnBattery") else {
            wasOnBattery = false
            return
        }
        let onBattery = Self.isOnBattery()
        defer { wasOnBattery = onBattery }
        if onBattery, !wasOnBattery, engine.phase != .snoozed {
            print("twen: on battery, pausing")
            pauseReason = .battery
            send(.snoozeRequested(until: nil))
        } else if !onBattery, pauseReason == .battery {
            print("twen: back on AC, resuming")
            pauseReason = nil
            send(.snoozeCancelled)
        }
    }

    private static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }

    private func send(_ event: EngineEvent) {
        let before = engine.phase
        let effects = engine.handle(event, at: Date())
        if engine.phase != before {
            print("twen: \(before.rawValue) -> \(engine.phase.rawValue) (accrued \(Int(engine.accrued))s)")
        }
        // The snooze ended without going through resume() — deadline expiry on a
        // tick, or a break request cutting the pause short. Drop the stale reason.
        if before == .snoozed, engine.phase != .snoozed, pauseReason != nil {
            pauseReason = nil
        }
        for effect in effects { desaturator.apply(effect) }
        // Re-anchored on every engine update, so it self-corrects after coalesced
        // ticks or an unlock that consumed part of the break.
        if engine.phase == .breakRunning {
            breakEndEstimate = Date().addingTimeInterval(engine.breakRemaining)
        } else if breakEndEstimate != nil {
            breakEndEstimate = nil
        }
    }

    // MARK: - Notification plumbing

    private func observeDistributed(_ name: String, _ handler: @escaping @MainActor @Sendable () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(name), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated(handler) }
    }

    private func observeWorkspace(_ name: Notification.Name, _ handler: @escaping @MainActor @Sendable () -> Void) {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated(handler) }
    }
}
