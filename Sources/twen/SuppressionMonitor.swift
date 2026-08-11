import AppKit
import CoreMediaIO
import IOKit.pwr_mgt

/// Real suppression signals (Phase 3). `isSuppressed` is polled every 2s from AppModel's
/// tick, so every check must be cheap: no background threads, no caching machinery, just
/// short-circuiting in rough cost order — power assertions (the primary signal, covering
/// video, presentations, calls and games in one check) before the window-list scan.
///
/// The only state is `lastReported`, used to log transitions; detection itself is stateless.
final class SuppressionMonitor: SuppressionChecking {
    private var lastReported = false

    var isSuppressed: Bool {
        let signal = firstSignal()
        let suppressed = signal != nil
        if suppressed != lastReported {
            lastReported = suppressed
            print(suppressed ? "suppression: active \(activeSignals())" : "suppression: cleared")
        }
        return suppressed
    }

    /// Every currently-firing signal, e.g. ["power-assertion: Chrome"]. Evaluates all
    /// checks (no short-circuit) — for debugging, `--check-suppression`, and future UI.
    func activeSignals() -> [String] {
        signalStates().compactMap { name, detail in detail.map { "\(name): \($0)" } }
    }

    /// Each signal's name and current detail (nil when not firing), in check order.
    func signalStates() -> [(name: String, detail: String?)] {
        [
            ("power-assertion", displaySleepAssertion()),
            ("screen-shared", screenShared()),
            ("camera", cameraInUse()),
            ("fullscreen", fullscreenWindow()),
        ]
    }

    /// Cheapest-first, returning on the first hit so the steady state does minimal work.
    private func firstSignal() -> String? {
        if let s = displaySleepAssertion() { return "power-assertion: \(s)" }
        if let s = screenShared() { return "screen-shared: \(s)" }
        if let s = cameraInUse() { return "camera: \(s)" }
        if let s = fullscreenWindow() { return "fullscreen: \(s)" }
        return nil
    }

    // MARK: - Signal 1: power assertions (primary)

    /// True display-sleep prevention is the strongest "the user is watching, not typing"
    /// signal: video players, presentation apps, video calls and games all assert it.
    private func displaySleepAssertion() -> String? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return nil }
        let matchTypes: Set<String> = [
            kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
            "NoDisplaySleepAssertion", // legacy name some apps still use
        ]
        for (pid, assertions) in byProcess {
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                      matchTypes.contains(type),
                      assertion[kIOPMAssertionLevelKey as String] as? Int ?? kIOPMAssertionLevelOn
                          == kIOPMAssertionLevelOn
                else { continue }
                return processName(pid: pid.int32Value)
            }
        }
        return nil
    }

    // MARK: - Signal 2: screen sharing / recording (best effort)

    /// The window server sets CGSSessionScreenIsShared while the legacy sharing path is
    /// active: Screen Sharing.app / Apple Remote Desktop and similar VNC-style control.
    /// It does NOT catch ScreenCaptureKit capture — Zoom/Meet/Teams screen share, OBS,
    /// QuickTime or Cmd-Shift-5 recordings — which never flips this flag. In practice
    /// most of those hold a PreventUserIdleDisplaySleep assertion or run the camera, so
    /// signals 1 and 3 cover them; this is a cheap extra net, not the real detector.
    private func screenShared() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session["CGSSessionScreenIsShared"] as? Bool == true
        else { return nil }
        return "session flag set"
    }

    // MARK: - Signal 3: camera in use (likely video call)

    /// kCMIODevicePropertyDeviceIsRunningSomewhere is readable without camera permission:
    /// it asks "is anyone using this device", not for frames.
    private func cameraInUse() -> String? {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &dataSize) == 0,
              dataSize > 0 else { return nil }
        var devices = [CMIOObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<CMIOObjectID>.size)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &devicesAddress, 0, nil, dataSize, &dataUsed, &devices) == 0
        else { return nil }

        var runningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        for device in devices {
            var running: UInt32 = 0
            var used: UInt32 = 0
            guard CMIOObjectGetPropertyData(
                device, &runningAddress, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &used, &running
            ) == 0 else { continue }
            if running != 0 { return deviceName(device) ?? "device \(device)" }
        }
        return nil
    }

    private func deviceName(_ device: CMIOObjectID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var name: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &name
        ) == 0 else { return nil }
        return name?.takeRetainedValue() as String?
    }

    // MARK: - Signal 4: native fullscreen

    /// A normal-layer (0) window whose bounds exactly cover a display. CGWindowList uses
    /// global top-left-origin coordinates, so compare against CGDisplayBounds (same space),
    /// never NSScreen.frame (bottom-left-origin). Our own desaturation windows live at
    /// shielding level, not layer 0, but skip our pid anyway to be defensive.
    private func fullscreenWindow() -> String? {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount) == .success,
              displayCount > 0 else { return nil }
        let displayBounds = displays.prefix(Int(displayCount)).map(CGDisplayBounds)

        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID != myPID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  displayBounds.contains(bounds)
            else { continue }
            return window[kCGWindowOwnerName as String] as? String ?? processName(pid: ownerPID)
        }
        return nil
    }

    // MARK: - Helpers

    private func processName(pid: pid_t) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [UInt8](repeating: 0, count: 256)
        let length = buffer.withUnsafeMutableBytes {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        if length > 0 { return String(decoding: buffer.prefix(Int(length)), as: UTF8.self) }
        return "pid \(pid)"
    }
}
