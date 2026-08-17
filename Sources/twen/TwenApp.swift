import SwiftUI
import TwenCore

/// Entry point called by the `twen` executable's main.swift. This module is a
/// library (for Xcode previews), so `@main` can't live here.
@MainActor
public func twenMain() {
    TwenApp.main()
}

struct TwenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar UI is AppKit (MenuBarController); SwiftUI only hosts Settings.
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil) // logs are our only eyes when run headless; don't buffer them
        // LSUIElement in the bundled Info.plist covers `make app`; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        // Before the flag switch: the status item exists only through the
        // controller now, and the probes assert against it.
        menuBar = MenuBarController()
        if CommandLine.arguments.contains("--demo-ramp") {
            runRampDemo()
        } else if CommandLine.arguments.contains("--check-suppression") {
            runSuppressionCheck()
        } else if CommandLine.arguments.contains("--exercise-settings") {
            runSettingsExercise()
        } else if CommandLine.arguments.contains("--probe-menu") {
            runMenuProbe()
        } else if CommandLine.arguments.contains("--probe-settings") {
            runSettingsOpenProbe()
        } else if CommandLine.arguments.contains("--probe-countdown") {
            runCountdownProbe()
        } else {
            AppModel.shared.start()
            let hotkey = AppModel.shared.hotkey
            hotkey.onPressed = { [weak self] in
                AppModel.shared.requestBreak() // break starts before the menu renders its state
                // Deferred: performClick tracks the menu synchronously; don't
                // park the Carbon callback frame for the whole browse.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.menuBar?.openMenu() }
                }
            }
            hotkey.register()
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

    /// Structural smoke test of the status item and menu — headless-safe, so it
    /// must never performClick: a real NSMenu opened without a user enters a
    /// tracking loop that never ends. Asserts the parts a launch can't miss:
    /// item wiring, phase text, enablement, and the displayed key equivalent.
    private func runMenuProbe() {
        guard let menuBar else { exit(1) }
        var failures = 0
        func expect(_ label: String, _ ok: Bool) {
            if !ok { failures += 1 }
            print("menu: \(label) \(ok ? "ok" : "FAIL")")
        }
        menuBar.refresh()
        expect("status button exists", menuBar.statusItem.button != nil)
        expect("button has image", menuBar.statusItem.button?.image != nil)
        expect("item count", menuBar.menu.items.count == 9)
        expect("status line disabled", !menuBar.statusLine.isEnabled)
        expect("status line has text", !menuBar.statusLine.title.isEmpty)
        expect("break item enabled while waiting", menuBar.breakItem.isEnabled)
        expect("pause visible / resume hidden",
               !menuBar.pauseItem.isHidden && menuBar.resumeItem.isHidden)
        expect("pause submenu has 2 items", menuBar.pauseItem.submenu?.items.count == 2)
        let settings = SettingsStore.shared
        let wantedKey = HotkeyManager.keyEquivalent(for: UInt32(settings.hotkeyKeyCode)) ?? ""
        expect("break key equivalent matches hotkey", menuBar.breakItem.keyEquivalent == wantedKey)
        expect("break key modifier mask matches hotkey",
               wantedKey.isEmpty || menuBar.breakItem.keyEquivalentModifierMask
                == HotkeyManager.menuModifierMask(carbon: UInt32(settings.hotkeyModifiers)))
        print("menu: probe \(failures == 0 ? "passed" : "FAILED (\(failures))")")
        exit(failures == 0 ? 0 : 1)
    }

    /// Guards the Settings-opening path: EnvironmentValues().openSettings() on
    /// macOS 14+ is undocumented-but-standard, so verify per OS release that it
    /// still summons the SwiftUI Settings scene. Opens a real window briefly.
    private func runSettingsOpenProbe() {
        menuBar?.openSettings()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            let opened = NSApp.windows.contains {
                $0.isVisible && (
                    $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
                    || $0.title.localizedCaseInsensitiveContains("settings")
                )
            }
            print("settings-open: probe \(opened ? "passed" : "FAILED")")
            exit(opened ? 0 : 1)
        }
    }

    /// Starts a real break (TWEN_FAST recommended) and samples the published menu
    /// bar countdown once per second: every sample must be exactly two digits and
    /// the sequence must decrease, and it must clear after the break ends. Guards
    /// the fixed-width guarantee — a launch smoke test never sees this path.
    private func runCountdownProbe() {
        AppModel.shared.start()
        Task {
            let model = AppModel.shared
            try? await Task.sleep(for: .seconds(1))
            model.requestBreak()
            var samples: [String] = []
            var widths: Set<CGFloat> = []
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                if let text = model.menuCountdown { samples.append(text) }
                if let statusWindow = NSApp.windows.first(where: {
                    $0.className.contains("NSStatusBarWindow")
                }) {
                    widths.insert(statusWindow.frame.width)
                }
            }
            // Outlast the break's remaining ~(length - 5)s plus a 2s engine tick.
            let breakLength = model.engine.config.breakLength
            try? await Task.sleep(for: .seconds(max(breakLength - 5, 0) + 4))
            let cleared = model.menuCountdown == nil
            let allTwoDigits = !samples.isEmpty && samples.allSatisfy {
                $0.count == 2 && $0.allSatisfy(\.isNumber)
            }
            // 1s sampling aliases against a 1s display, so equal neighbors are
            // fine; the sequence must never increase and must move overall.
            let decreasing = zip(samples, samples.dropFirst()).allSatisfy { $0 >= $1 }
                && samples.first ?? "" > samples.last ?? ""
            // The whole point of the zero-padded label: one width, start to end.
            let widthStable = widths.count == 1
            print("countdown: samples \(samples) widths \(widths.sorted()) cleared=\(cleared)")
            let ok = allTwoDigits && decreasing && cleared && widthStable
            print("countdown: probe \(ok ? "passed" : "FAILED")")
            exit(ok ? 0 : 1)
        }
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
