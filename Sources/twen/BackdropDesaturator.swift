import AppKit
import QuartzCore
import TwenCore

/// The spike-proven backend (spike/a-backdrop): one click-through window per display
/// hosting a private CABackdropLayer whose colorSaturate filter desaturates everything
/// rendered behind it. Windows exist only while saturation < 1, so the app has zero
/// window-server footprint when the screen is at full color.
///
/// Private API risk is contained here: if CABackdropLayer/CAFilter ever stop resolving,
/// `isSupported` goes false and AppModel falls back (overlay backend planned in Phase 3).
@MainActor
final class BackdropDesaturator: Desaturating {
    static var isSupported: Bool {
        NSClassFromString("CABackdropLayer") as? CALayer.Type != nil
            && NSClassFromString("CAFilter") as? NSObject.Type != nil
    }

    private static let filterKeyPath = "filters.saturate.inputAmount"
    private static let animationKey = "saturationRamp"

    private var windows: [NSWindow] = []
    private var backdropLayers: [CALayer] = []
    private var modelSaturation: Double = 1
    /// The in-flight ramp, kept so a display hot-plug can rebuild and rejoin it.
    private var activeRamp: (target: Double, end: Date)?
    private var teardownTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func apply(_ effect: EngineEffect) {
        switch effect {
        case let .ramp(toSaturation, over): ramp(to: toSaturation, over: over)
        case let .hold(atSaturation): hold(at: atSaturation)
        }
    }

    // MARK: - Effects

    private func ramp(to target: Double, over duration: TimeInterval) {
        teardownTask?.cancel()
        if target < 1, windows.isEmpty { buildWindows(saturation: 1) }
        guard !windows.isEmpty else { return } // full color -> full color: nothing to do

        let from = currentVisualSaturation()
        modelSaturation = target
        activeRamp = duration > 0 ? (target, Date().addingTimeInterval(duration)) : nil
        print("desaturator: ramp \(fmt(from)) -> \(fmt(target)) over \(Int(duration))s")
        addRampAnimation(from: from, to: target, duration: duration)

        if target >= 1 {
            // Remove the windows once the restore finishes — unless a new effect lands first.
            teardownTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 0.3))
                guard !Task.isCancelled, let self, self.modelSaturation >= 1 else { return }
                self.teardown()
            }
        }
    }

    private func hold(at fallback: Double) {
        teardownTask?.cancel()
        guard !windows.isEmpty else { return }
        // Trust the presentation layer over the engine's bookkeeping: it is what
        // the user is actually seeing, and the two can drift by up to one tick.
        let value = currentVisualSaturation(fallback: fallback)
        modelSaturation = value
        activeRamp = nil
        print("desaturator: hold at \(fmt(value))")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in backdropLayers {
            layer.setValue(value, forKeyPath: Self.filterKeyPath)
            layer.removeAnimation(forKey: Self.animationKey)
        }
        CATransaction.commit()
    }

    // MARK: - Core Animation

    private func addRampAnimation(from: Double, to: Double, duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in backdropLayers {
            layer.setValue(to, forKeyPath: Self.filterKeyPath)
            guard duration > 0 else {
                layer.removeAnimation(forKey: Self.animationKey)
                continue
            }
            let animation = CABasicAnimation(keyPath: Self.filterKeyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: Self.animationKey)
        }
        CATransaction.commit()
    }

    private func currentVisualSaturation(fallback: Double? = nil) -> Double {
        if let layer = backdropLayers.first,
           let value = (layer.presentation() ?? layer).value(forKeyPath: Self.filterKeyPath) as? Double {
            return value
        }
        return fallback ?? modelSaturation
    }

    // MARK: - Window lifecycle

    private func buildWindows(saturation: Double) {
        guard windows.isEmpty else { return }
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
            print("desaturator: private classes unavailable; no visual effect")
            return
        }

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
            window.sharingType = .none // screenshots and screen shares stay full color

            let contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            contentView.wantsLayer = true
            window.contentView = contentView
            guard let hostLayer = contentView.layer else { continue }

            let backdrop = backdropClass.init()
            backdrop.frame = hostLayer.bounds
            backdrop.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            if backdrop.responds(to: NSSelectorFromString("setWindowServerAware:")) {
                backdrop.setValue(true, forKey: "windowServerAware")
            }
            guard let filter = Self.makeSaturationFilter(filterClass, amount: saturation) else { continue }
            backdrop.filters = [filter]
            hostLayer.addSublayer(backdrop)

            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            windows.append(window)
            backdropLayers.append(backdrop)
        }
        modelSaturation = saturation
        print("desaturator: created \(windows.count) backdrop window(s)")
    }

    private static func makeSaturationFilter(_ filterClass: NSObject.Type, amount: Double) -> NSObject? {
        let factory = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: factory),
              let unmanaged = filterClass.perform(factory, with: "colorSaturate" as NSString),
              let filter = unmanaged.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue("saturate", forKey: "name")
        filter.setValue(amount, forKey: "inputAmount")
        return filter
    }

    private func teardown() {
        guard !windows.isEmpty else { return }
        print("desaturator: full color restored; removing \(windows.count) window(s)")
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        backdropLayers = []
        modelSaturation = 1
        activeRamp = nil
    }

    private func screensChanged() {
        guard !windows.isEmpty else { return }
        let value = currentVisualSaturation()
        let ramp = activeRamp
        print("desaturator: screens changed; rebuilding at \(fmt(value))")
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        backdropLayers = []
        buildWindows(saturation: value)
        if let ramp, ramp.end > Date() {
            modelSaturation = ramp.target
            activeRamp = ramp
            addRampAnimation(from: value, to: ramp.target, duration: ramp.end.timeIntervalSinceNow)
        }
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
