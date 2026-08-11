// Spike A: full-screen gradual desaturation via private CABackdropLayer + CAFilter(colorSaturate).
// Prototype-grade throwaway code for the "twen" menu bar app spike.
// Timeline: saturation 1.0 -> 0.0 over 4s, hold 8s, 0.0 -> 1.0 over 2s, then exit.

import AppKit
import QuartzCore

// Unbuffered stdout so the orchestrator sees PHASE lines in real time.
setbuf(stdout, nil)

// Durations: ./proto-a [rampDown] [hold] [rampUp]  (seconds, defaults 4/8/2)
let cliArgs = CommandLine.arguments
let rampDownDuration = cliArgs.count > 1 ? Double(cliArgs[1]) ?? 4.0 : 4.0
let holdDuration = cliArgs.count > 2 ? Double(cliArgs[2]) ?? 8.0 : 8.0
let rampUpDuration = cliArgs.count > 3 ? Double(cliArgs[3]) ?? 2.0 : 2.0

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// --- Resolve private classes via the ObjC runtime ---

guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
    print("ERROR: CABackdropLayer is not available on this system (NSClassFromString returned nil).")
    exit(1)
}

guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
    print("ERROR: CAFilter is not available on this system (NSClassFromString returned nil).")
    exit(1)
}

/// Create a private CAFilter of type "colorSaturate", named "saturate", inputAmount 1.0.
func makeSaturationFilter() -> NSObject? {
    let factorySelector = NSSelectorFromString("filterWithType:")
    guard filterClass.responds(to: factorySelector),
          let unmanaged = filterClass.perform(factorySelector, with: "colorSaturate" as NSString),
          let filter = unmanaged.takeUnretainedValue() as? NSObject
    else {
        return nil
    }
    filter.setValue("saturate", forKey: "name")
    filter.setValue(1.0, forKey: "inputAmount")
    return filter
}

// --- One overlay window + backdrop layer per screen ---

var overlayWindows: [NSWindow] = []
var backdropLayers: [CALayer] = []

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
    window.isReleasedWhenClosed = false

    let contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    contentView.wantsLayer = true
    window.contentView = contentView

    guard let hostLayer = contentView.layer else {
        print("ERROR: contentView has no backing layer.")
        exit(1)
    }

    let backdrop = backdropClass.init()
    backdrop.frame = hostLayer.bounds
    backdrop.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

    // Opt the backdrop into sampling other windows' content, if the key exists.
    // CALayer tolerates unknown KVC keys, but be defensive anyway.
    if backdrop.responds(to: NSSelectorFromString("setWindowServerAware:")) {
        backdrop.setValue(true, forKey: "windowServerAware")
        print("INFO: windowServerAware = true on backdrop layer.")
    } else {
        print("INFO: windowServerAware setter not present; continuing without it.")
    }

    guard let filter = makeSaturationFilter() else {
        print("ERROR: could not create CAFilter(colorSaturate) via +filterWithType:.")
        exit(1)
    }
    backdrop.filters = [filter]

    hostLayer.addSublayer(backdrop)

    window.setFrame(screen.frame, display: true)
    window.orderFrontRegardless()

    overlayWindows.append(window)
    backdropLayers.append(backdrop)
}

if backdropLayers.isEmpty {
    print("ERROR: no screens found; nothing to desaturate.")
    exit(1)
}

print("INFO: created \(backdropLayers.count) overlay window(s) with CABackdropLayer.")

// --- Saturation ramps ---

func rampSaturation(from: Double, to: Double, duration: TimeInterval) {
    for layer in backdropLayers {
        let animation = CABasicAnimation(keyPath: "filters.saturate.inputAmount")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Set the model value so the end state sticks after the animation completes.
        layer.setValue(to, forKeyPath: "filters.saturate.inputAmount")
        layer.add(animation, forKey: "saturationRamp")
    }
}

// --- Timeline: ramp down, hold, ramp up, exit ---

print("PHASE: ramping-down")
rampSaturation(from: 1.0, to: 0.0, duration: rampDownDuration)

DispatchQueue.main.asyncAfter(deadline: .now() + rampDownDuration) {
    print("PHASE: holding")
}

DispatchQueue.main.asyncAfter(deadline: .now() + rampDownDuration + holdDuration) {
    print("PHASE: restoring")
    rampSaturation(from: 0.0, to: 1.0, duration: rampUpDuration)
}

DispatchQueue.main.asyncAfter(deadline: .now() + rampDownDuration + holdDuration + rampUpDuration + 0.2) {
    print("PHASE: done")
    exit(0)
}

app.run()
