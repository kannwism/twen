import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @StateObject private var recorder = HotkeyRecorder()

    @State private var launchAtLogin = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            timingSection
            shortcutSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear(perform: refreshLoginStatus)
        .onDisappear { recorder.cancel() } // never leave the hotkey unregistered
    }

    // MARK: - Timing

    private var timingSection: some View {
        Section("Timing") {
            timingRow("Work interval", value: $store.workInterval,
                      in: SettingsStore.workIntervalRange, step: 60)
            timingRow("Break length", value: $store.breakLength,
                      in: SettingsStore.breakLengthRange, step: 5)
            timingRow("Fade duration", value: $store.rampDuration,
                      in: SettingsStore.rampDurationRange, step: 10)
            timingRow("Pause after idle", value: $store.idlePause,
                      in: SettingsStore.idlePauseRange, step: 10)
            timingRow("Reset after idle", value: $store.idleReset,
                      in: (store.idlePause + SettingsStore.idleResetMargin)...SettingsStore.idleResetDisplayMax,
                      step: 30)
            timingRow("Break counts after", value: $store.breakSatisfyIdle,
                      in: SettingsStore.breakSatisfyIdleMinimum...store.idleReset, step: 10)
        }
    }

    private func timingRow(
        _ title: String,
        value: Binding<TimeInterval>,
        in range: ClosedRange<TimeInterval>,
        step: TimeInterval
    ) -> some View {
        LabeledContent(title) {
            // Value first (right-aligned column), bare stepper last: the chevrons
            // land on one shared right edge regardless of the value's text width.
            HStack(spacing: 8) {
                Text(Self.duration(value.wrappedValue))
                    .monospacedDigit()
                    .frame(minWidth: 76, alignment: .trailing)
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }

    /// Human units: whole minutes where they fit, seconds elsewhere.
    private static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s.isMultiple(of: 60) { return "\(s / 60) min" }
        return "\(s / 60) min \(s % 60) s"
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        Section("Shortcut") {
            LabeledContent("Start break") {
                HStack(spacing: 8) {
                    Text(recorder.isRecording ? "press shortcut…" : store.comboDescription)
                        .foregroundStyle(recorder.isRecording ? .secondary : .primary)
                    Button(recorder.isRecording ? "Cancel" : "Record…") {
                        recorder.isRecording ? recorder.cancel() : recorder.begin()
                    }
                }
            }
            if let hint = recorder.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            if launchAtLoginNeedsApproval {
                Text("macOS needs your approval in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Pause while on battery", isOn: $store.pauseOnBattery)
        }
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    /// Registering only truly sticks for the installed copy (/Applications/twen.app);
    /// from a dev build it may register the build path or fail. Errors surface
    /// inline and the toggle always snaps back to the real status.
    private func setLaunchAtLogin(_ enable: Bool) {
        launchAtLoginError = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            print("twen: launch at login \(enable ? "registered" : "unregistered")")
        } catch {
            print("twen: launch at login failed: \(error.localizedDescription)")
            launchAtLoginError = error.localizedDescription
        }
        refreshLoginStatus()
    }
}

// MARK: - Hotkey recorder

/// Captures the next keydown as the new global shortcut. While recording, the
/// current hotkey is unregistered so pressing the same combo re-records instead of
/// triggering a break; every path out (capture, cancel, Escape, window close via
/// SettingsView.onDisappear) re-registers.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hint: String?

    private var monitor: Any?

    func begin() {
        guard monitor == nil else { return }
        isRecording = true
        hint = "Press a key with ⌘, ⌥ or ⌃ — Esc cancels."
        AppModel.shared.hotkey.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.capture(event) }
            return nil // swallow keystrokes while recording
        }
    }

    func cancel() {
        guard isRecording else { return }
        finish()
    }

    private func capture(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            finish()
            return
        }
        var carbon = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        // Plain keys (or shift-only) would swallow normal typing system-wide.
        guard carbon & (cmdKey | optionKey | controlKey) != 0 else {
            hint = "Include at least one of ⌘, ⌥ or ⌃."
            return
        }
        finish(newKeyCode: Int(event.keyCode), newModifiers: carbon)
    }

    /// Tears down the monitor and restores a registered hotkey: the new combo when
    /// one was captured (persist → re-register), the old one otherwise.
    private func finish(newKeyCode: Int? = nil, newModifiers: Int? = nil) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        hint = nil
        if let newKeyCode, let newModifiers {
            SettingsStore.shared.setHotkey(keyCode: newKeyCode, modifiers: newModifiers)
        } else {
            AppModel.shared.hotkey.register()
        }
    }
}
