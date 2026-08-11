import AppKit

/// Opens the MenuBarExtra popover programmatically, as if its status item were
/// clicked — so the hotkey can surface the break countdown without the mouse.
///
/// SwiftUI offers no public API for this (as of macOS 26). Our status item lives
/// in this process, though: find our NSStatusBarWindow, reach its status item via
/// KVC, and click its button. Every step is guarded, so if SwiftUI's internals
/// change this quietly does nothing — the break still starts, only the auto-opened
/// popover is lost.
@MainActor
enum MenuBarPresenter {
    static func openPopover() {
        guard !isPopoverVisible else { return } // performClick would toggle it CLOSED

        guard let statusWindow = NSApp.windows.first(where: {
            $0.className.contains("NSStatusBarWindow")
        }) else {
            print("menubar: status window not found; cannot auto-open popover")
            return
        }
        // KVC on an undefined key raises an ObjC exception; probe first.
        guard statusWindow.responds(to: NSSelectorFromString("statusItem")),
              let statusItem = statusWindow.value(forKey: "statusItem") as? NSStatusItem,
              let button = statusItem.button else {
            print("menubar: status item not reachable; cannot auto-open popover")
            return
        }
        button.performClick(nil)
    }

    /// The MenuBarExtra(.window) content panel, when open, is a visible window
    /// whose class name mentions MenuBarExtra.
    static var isPopoverVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.className.contains("MenuBarExtra") }
    }
}
