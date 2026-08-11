import AppKit
import TwenCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var engine: TwenEngine

    private let idleSource: any IdleSource
    private let suppression: any SuppressionChecking
    private let desaturator: any Desaturating
    private var pollTask: Task<Void, Never>?

    init(
        idleSource: any IdleSource = SystemIdleSource(),
        suppression: any SuppressionChecking = NoSuppression(),
        desaturator: any Desaturating = LoggingDesaturator()
    ) {
        self.idleSource = idleSource
        self.suppression = suppression
        self.desaturator = desaturator
        let fast = ProcessInfo.processInfo.environment["TWEN_FAST"] == "1"
        engine = TwenEngine(config: fast ? .fastDemo : EngineConfig())
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

    private func tick() {
        send(.tick(idle: idleSource.secondsSinceLastInput, suppressed: suppression.isSuppressed))
    }

    private func send(_ event: EngineEvent) {
        let before = engine.phase
        let effects = engine.handle(event, at: Date())
        if engine.phase != before {
            print("twen: \(before.rawValue) -> \(engine.phase.rawValue) (accrued \(Int(engine.accrued))s)")
        }
        for effect in effects { desaturator.apply(effect) }
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
