import SwiftUI
import TwenCore

@main
struct TwenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private var menuIcon: String {
        switch model.engine.phase {
        case .waiting, .paused: "eye.slash"
        case .working: "eye"
        case .ramping, .gray: "eye.trianglebadge.exclamationmark"
        case .breakRunning: "timer"
        case .breakSatisfied: "checkmark.circle"
        case .snoozed: "zzz"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil) // logs are our only eyes when run headless; don't buffer them
        // LSUIElement in the bundled Info.plist covers `make app`; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--demo-ramp") {
            runRampDemo()
        } else if CommandLine.arguments.contains("--check-suppression") {
            runSuppressionCheck()
        } else if CommandLine.arguments.contains("--exercise-settings") {
            runSettingsExercise()
        } else {
            AppModel.shared.start()
            AppModel.shared.hotkey.register()
        }
    }

    /// Prints each suppression signal's current state and the overall verdict, then exits.
    /// Touches nothing visual — a permanent diagnostic, like --demo-ramp is for the ramp.
    private func runSuppressionCheck() {
        let monitor = SuppressionMonitor()
        for (name, detail) in monitor.signalStates() {
            print("suppression: \(name) = \(detail ?? "none")")
        }
        let signals = monitor.activeSignals()
        print("suppression: verdict = \(signals.isEmpty ? "clear" : "suppressed \(signals)")")
        NSApp.terminate(nil)
    }

    /// Drives SettingsStore's setters programmatically against a throwaway defaults
    /// suite — the exact path a Settings-window edit takes. Exists because an
    /// unguarded @Published didSet self-assignment once recursed to a stack-overflow
    /// crash on the first edit, which headless launch smoke tests can never catch.
    private func runSettingsExercise() {
        let suiteName = "dev.twen.settings-exercise"
        guard let suite = UserDefaults(suiteName: suiteName) else { exit(1) }
        suite.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: suite)
        var failures = 0
        func expect(_ label: String, _ actual: TimeInterval, _ wanted: TimeInterval) {
            let ok = actual == wanted
            if !ok { failures += 1 }
            print("settings: \(label) = \(Int(actual)) (want \(Int(wanted))) \(ok ? "ok" : "FAIL")")
        }
        store.workInterval = 25 * 60                       // plain in-range change
        expect("workInterval in-range", store.workInterval, 25 * 60)
        store.workInterval = 1                             // clamps to floor
        expect("workInterval clamped", store.workInterval, 5 * 60)
        store.idlePause = 600                              // cascades idleReset up
        expect("idlePause", store.idlePause, 600)
        expect("idleReset cascaded", store.idleReset, 600 + SettingsStore.idleResetMargin)
        store.idleReset = 60                               // below floor, clamps back
        expect("idleReset clamped", store.idleReset, 600 + SettingsStore.idleResetMargin)
        store.breakSatisfyIdle = 10_000                    // clamps to idleReset
        expect("breakSatisfyIdle clamped", store.breakSatisfyIdle, store.idleReset)
        suite.removePersistentDomain(forName: suiteName)
        print("settings: exercise \(failures == 0 ? "passed" : "FAILED (\(failures))")")
        exit(failures == 0 ? 0 : 1)
    }

    /// Exercises the visual path end to end without the timer: ramp down, hold
    /// mid-flight, resume, restore, teardown. Kept as a permanent tuning tool.
    private func runRampDemo() {
        let desaturator: any Desaturating =
            BackdropDesaturator.isSupported ? BackdropDesaturator() : LoggingDesaturator()
        Task {
            print("demo: ramp to gray over 4s")
            desaturator.apply(.ramp(toSaturation: 0, over: 4))
            try? await Task.sleep(for: .seconds(2))
            print("demo: hold mid-ramp")
            desaturator.apply(.hold(atSaturation: 0.5))
            try? await Task.sleep(for: .seconds(2))
            print("demo: resume to gray over 2s")
            desaturator.apply(.ramp(toSaturation: 0, over: 2))
            try? await Task.sleep(for: .seconds(4))
            print("demo: restore over 3s")
            desaturator.apply(.ramp(toSaturation: 1, over: 3))
            try? await Task.sleep(for: .seconds(4))
            print("demo: done")
            NSApp.terminate(nil)
        }
    }
}
