// Spike B: PUBLIC-API fallback for "screen draining to gray".
// Per-display click-through gray overlay window + gamma contrast reduction.
// Prototype-grade throwaway code for twen.
//
// Build: swiftc main.swift -o proto-b -framework AppKit -framework QuartzCore
// Run:   ./proto-b   (ramps in 4s, holds 8s, ramps out 2s, restores gamma, exits)
//
// Safety note: gamma table changes made via CGSetDisplayTransferByFormula are
// automatically reverted by the window server when the process exits, so even
// a crash cannot leave the screen dimmed. We still restore explicitly with
// CGDisplayRestoreColorSyncSettings() for cleanliness.

import AppKit
import QuartzCore

// MARK: - Config

// Durations: ./proto-b [rampIn] [hold] [rampOut]  (seconds, defaults 4/8/2)
let cliArgs = CommandLine.arguments
let rampInDuration: TimeInterval = cliArgs.count > 1 ? Double(cliArgs[1]) ?? 4.0 : 4.0
let holdDuration: TimeInterval = cliArgs.count > 2 ? Double(cliArgs[2]) ?? 8.0 : 8.0
let rampOutDuration: TimeInterval = cliArgs.count > 3 ? Double(cliArgs[3]) ?? 2.0 : 2.0

let overlayTargetOpacity: Float = 0.35

// Gamma output-range endpoints at full effect (gamma exponent stays 1.0).
let gammaMinTarget: CGGammaValue = 0.08
let gammaMaxTarget: CGGammaValue = 0.92

let gammaTimerInterval: TimeInterval = 0.1 // ~10 Hz

// MARK: - Helpers

func logPhase(_ line: String) {
    print(line)
    fflush(stdout)
}

func activeDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
}

/// t = 0 → normal (min 0.0, max 1.0); t = 1 → full effect (min 0.08, max 0.92).
func applyGammaContrast(_ t: Float) {
    let tt = CGGammaValue(max(0, min(1, t)))
    let minV = 0.0 + (gammaMinTarget - 0.0) * tt
    let maxV = 1.0 + (gammaMaxTarget - 1.0) * tt
    for display in activeDisplayIDs() {
        _ = CGSetDisplayTransferByFormula(
            display,
            minV, maxV, 1.0, // red:   min, max, gamma
            minV, maxV, 1.0, // green: min, max, gamma
            minV, maxV, 1.0  // blue:  min, max, gamma
        )
    }
}

// MARK: - App + overlay windows

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var overlayWindows: [NSWindow] = []

for screen in NSScreen.screens {
    let window = NSWindow(
        contentRect: screen.frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    window.ignoresMouseEvents = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

    let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    view.wantsLayer = true
    view.layer?.backgroundColor = CGColor(gray: 0.5, alpha: 1.0)
    view.layer?.opacity = 0
    window.contentView = view

    window.orderFrontRegardless()
    overlayWindows.append(window)
}

func animateOverlays(to opacity: Float, duration: TimeInterval) {
    for window in overlayWindows {
        guard let layer = window.contentView?.layer else { continue }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = opacity
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.opacity = opacity // set model value so it sticks after the animation
        layer.add(anim, forKey: "opacity")
    }
}

// MARK: - Gamma ramp (Timer on main run loop, linear interpolation)

func rampGamma(from: Float, to: Float, duration: TimeInterval) {
    let startTime = Date()
    let timer = Timer(timeInterval: gammaTimerInterval, repeats: true) { t in
        let elapsed = Date().timeIntervalSince(startTime)
        let fraction = Float(min(elapsed / duration, 1.0))
        applyGammaContrast(from + (to - from) * fraction)
        if fraction >= 1.0 {
            t.invalidate()
        }
    }
    RunLoop.main.add(timer, forMode: .common)
}

// MARK: - Timeline

logPhase("PHASE: ramping-down")
animateOverlays(to: overlayTargetOpacity, duration: rampInDuration)
rampGamma(from: 0, to: 1, duration: rampInDuration)

DispatchQueue.main.asyncAfter(deadline: .now() + rampInDuration) {
    logPhase("PHASE: holding")
}

DispatchQueue.main.asyncAfter(deadline: .now() + rampInDuration + holdDuration) {
    logPhase("PHASE: restoring")
    animateOverlays(to: 0, duration: rampOutDuration)
    rampGamma(from: 1, to: 0, duration: rampOutDuration)
}

DispatchQueue.main.asyncAfter(
    deadline: .now() + rampInDuration + holdDuration + rampOutDuration + 0.3
) {
    CGDisplayRestoreColorSyncSettings()
    logPhase("PHASE: done")
    exit(0)
}

app.run()
