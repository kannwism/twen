import AppKit
import Combine
import SwiftUI
import TwenCore

/// The status item and its real NSMenu — twen's entire menu bar UI. Replaces the
/// old MenuBarExtra(.window) popover: a native menu needs no styling replication,
/// and opening it from the hotkey is public API (performClick) instead of a KVC
/// hack into SwiftUI internals.
///
/// All items are created once; phase changes only toggle title/isEnabled/isHidden.
/// Never add or remove items: the menu can be mid-tracking when a snooze expires,
/// and restructuring a tracking menu is undefined.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    // Internal (not private) so the --probe-menu smoke test can assert on them.
    let statusItem: NSStatusItem
    let menu = NSMenu()
    let statusLine = NSMenuItem()
    let detailLine = NSMenuItem()
    let breakItem = NSMenuItem()
    let pauseItem = NSMenuItem()
    let resumeItem = NSMenuItem()
    let updateItem = NSMenuItem()
    let settingsItem = NSMenuItem()
    let quitItem = NSMenuItem()

    private var refreshTimer: Timer?
    private(set) var isMenuOpen = false
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel = .shared) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        // NSMenuItem.target is strong, so controller → menu → items → controller
        // is a retain cycle. Deliberate: this object lives as long as the app.
        statusItem.menu = menu
        observeModel()
        updateButton(countdown: model.menuCountdown, phase: model.engine.phase)
        refresh()
    }

    // MARK: - Menu construction

    private func buildMenu() {
        menu.delegate = self
        // Manual enablement: state changes while the menu is open (hotkey, timer),
        // and only an explicit isEnabled from refresh() can gray items live.
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        detailLine.isEnabled = false

        breakItem.title = "Take a break now"
        breakItem.target = self
        breakItem.action = #selector(takeBreak)
        // Show exactly what Carbon registered; don't let AppKit relocalize it.
        breakItem.allowsAutomaticKeyEquivalentLocalization = false

        pauseItem.title = "Pause"
        let pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        pauseMenu.addItem(subitem("For 1 hour", #selector(pauseOneHour)))
        pauseMenu.addItem(subitem("Until tomorrow", #selector(pauseUntilTomorrow)))
        pauseItem.submenu = pauseMenu

        resumeItem.title = "Resume"
        resumeItem.target = self
        resumeItem.action = #selector(resume)

        // Hidden until UpdateChecker surfaces a newer release; title set in refresh().
        updateItem.isHidden = true
        updateItem.target = self
        updateItem.action = #selector(openReleasePage)

        settingsItem.title = "Settings…"
        settingsItem.target = self
        settingsItem.action = #selector(openSettings)

        quitItem.title = "Quit twen"
        quitItem.target = self
        quitItem.action = #selector(quit)
        quitItem.keyEquivalent = "q"

        menu.addItem(statusLine)
        menu.addItem(detailLine)
        menu.addItem(.separator())
        menu.addItem(breakItem)
        menu.addItem(pauseItem)
        menu.addItem(resumeItem)
        menu.addItem(.separator())
        menu.addItem(updateItem)
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
    }

    private func subitem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Only the button icon needs push updates (it's visible without the menu);
    /// item titles are refreshed in menuNeedsUpdate and by the open-menu timer.
    /// Direct synchronous sinks — no .receive(on: RunLoop.main), which enqueues
    /// in .default mode and would freeze exactly while a menu is tracking.
    private func observeModel() {
        model.$menuCountdown.combineLatest(model.$engine)
            .sink { countdown, engine in
                MainActor.assumeIsolated { [weak self] in
                    self?.updateButton(countdown: countdown, phase: engine.phase)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    /// One pass over every mutable item property; called before display
    /// (menuNeedsUpdate) and once per second while the menu is open.
    func refresh() {
        let engine = model.engine
        statusLine.title = statusText(engine)
        let detail = detailText(engine)
        detailLine.title = detail ?? ""
        detailLine.isHidden = detail == nil
        breakItem.isEnabled = engine.phase != .breakRunning
        let snoozed = engine.phase == .snoozed
        pauseItem.isHidden = snoozed
        resumeItem.isHidden = !snoozed
        if let update = model.updateChecker.available {
            updateItem.title = "Update available: \(update.version)…"
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true
        }
        applyBreakKeyEquivalent()
    }

    private func applyBreakKeyEquivalent() {
        let settings = SettingsStore.shared
        if let key = HotkeyManager.keyEquivalent(for: UInt32(settings.hotkeyKeyCode)) {
            breakItem.keyEquivalent = key
            breakItem.keyEquivalentModifierMask =
                HotkeyManager.menuModifierMask(carbon: UInt32(settings.hotkeyModifiers))
        } else {
            breakItem.keyEquivalent = ""
        }
    }

    private func statusText(_ engine: TwenEngine) -> String {
        switch engine.phase {
        case .waiting, .working:
            let remaining = engine.config.workInterval - engine.accrued
            guard remaining > 0 else { return "Break coming up" }
            return "Next break in ~\(Int((remaining / 60).rounded(.up)))m"
        case .paused:
            return "Paused — you're away"
        case .ramping:
            return "Time to look away — fading to gray"
        case .gray:
            return "Screen's waiting — take your break"
        case .breakRunning:
            return "Break: \(breakSecondsRemaining(engine))s — look 20 feet away"
        case .breakSatisfied:
            return "Break taken — color returns when you're back"
        case .snoozed:
            return pausedLine
        }
    }

    /// Prefers the wall-clock estimate (re-anchored every engine update) so the
    /// 1s menu timer shows a smooth countdown between 2s engine ticks.
    private func breakSecondsRemaining(_ engine: TwenEngine) -> Int {
        let remaining = model.breakEndEstimate?.timeIntervalSinceNow ?? engine.breakRemaining
        return max(0, Int(remaining.rounded(.up)))
    }

    private func detailText(_ engine: TwenEngine) -> String? {
        if model.isSuppressed {
            return "on hold — \(model.suppressionSignals.first ?? "video or presentation detected")"
        }
        let minutes = Int(engine.accrued / 60)
        switch engine.phase {
        case .waiting, .working, .paused, .ramping, .gray:
            return minutes >= 1 ? "Worked \(minutes)m" : nil
        case .breakRunning, .breakSatisfied, .snoozed:
            return nil
        }
    }

    /// "Paused until 14:30" / "Paused until tomorrow" / "Paused while on battery" / "Paused".
    private var pausedLine: String {
        switch model.pauseReason {
        case .battery:
            return "Paused while on battery"
        case .manual(let until?):
            if Calendar.current.isDateInToday(until) {
                return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "Paused until tomorrow"
        case .manual(nil), nil:
            return "Paused"
        }
    }

    // MARK: - Open / tracking lifecycle

    /// Programmatic open for the hotkey. performClick tracks the menu
    /// synchronously, and on an already-open item it would toggle it closed.
    func openMenu() {
        guard !isMenuOpen else { return }
        statusItem.button?.performClick(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        guard refreshTimer == nil else { return }
        // Menu tracking parks the run loop in eventTracking mode; a .common-modes
        // timer is the one guaranteed-live update path. It drives the model too:
        // the Task-based poll loop may stall while the menu is open, and the
        // dt-based engine makes the overlap harmless. 1s minimum — every poll
        // runs the full suppression checks.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.pollNow()
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions

    @objc private func takeBreak() { model.requestBreak() }
    @objc private func pauseOneHour() { model.pause(for: 60 * 60) }
    @objc private func pauseUntilTomorrow() { model.pauseUntilTomorrow() }
    @objc private func resume() { model.resume() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Deliberately just a link: brew-installed copies should update via brew, so
    /// the app never downloads anything itself — the release page explains both.
    @objc private func openReleasePage() {
        guard let url = model.updateChecker.available?.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Internal (not private): --probe-settings invokes it directly to verify
    /// the EnvironmentValues bridge still works on the running OS.
    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            // openSettings is app-global, so a fresh EnvironmentValues works from
            // AppKit. Undocumented but the standard bridge; the 13 selector below
            // is the documented-era fallback and unreliable on 14+.
            EnvironmentValues().openSettings()
        } else {
            let handled = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            if !handled { print("menubar: showSettingsWindow: not handled") }
        }
    }

    // MARK: - Status button icon

    private func updateButton(countdown: String?, phase: TwenPhase) {
        guard let button = statusItem.button else { return }
        // Image only, never image + title: the fixed canvas is what keeps the
        // status item from changing width mid-countdown.
        if let countdown {
            button.image = Self.countdownImage(countdown)
        } else {
            button.image = NSImage(systemSymbolName: Self.iconName(for: phase),
                                   accessibilityDescription: "twen")
        }
    }

    private static func iconName(for phase: TwenPhase) -> String {
        switch phase {
        case .waiting, .paused: "eye.slash"
        case .working: "eye"
        case .ramping, .gray: "eye.trianglebadge.exclamationmark"
        case .breakRunning: "timer"
        case .breakSatisfied: "checkmark.circle"
        case .snoozed: "zzz"
        }
    }

    /// The two digits rendered at menu bar text size on a canvas sized for "00".
    /// Monospaced digits make every pair the same width, but the fixed canvas is
    /// what guarantees it. Template image, so the system tints it like any icon.
    private static func countdownImage(_ text: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let canvas = ("00" as NSString).size(withAttributes: attributes)
        let size = NSSize(width: ceil(canvas.width), height: ceil(canvas.height))
        let image = NSImage(size: size, flipped: false) { rect in
            let textSize = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: (rect.width - textSize.width) / 2,
                            y: (rect.height - textSize.height) / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
