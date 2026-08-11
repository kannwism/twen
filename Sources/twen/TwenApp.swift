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
    }

    private var menuIcon: String {
        switch model.engine.phase {
        case .waiting, .paused: "eye.slash"
        case .working: "eye"
        case .ramping, .gray: "eye.trianglebadge.exclamationmark"
        case .breakRunning: "timer"
        case .breakSatisfied: "checkmark.circle"
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
        } else {
            AppModel.shared.start()
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
