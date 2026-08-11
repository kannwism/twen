import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcut via Carbon `RegisterEventHotKey` — the one API that
/// works without Accessibility permission (spec requirement). Default ⌥⌘B;
/// overridable via the `hotkeyKeyCode` / `hotkeyModifiers` UserDefaults keys
/// (Carbon virtual keycode and modifier flag values), written by SettingsStore.
@MainActor
final class HotkeyManager {
    // Mutated only on the main actor; nonisolated(unsafe) solely so the
    // nonisolated deinit can release them.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }

        let defaults = UserDefaults.standard
        let keyCode = UInt32(defaults.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_ANSI_B)
        let modifiers = UInt32(defaults.object(forKey: "hotkeyModifiers") as? Int ?? (cmdKey | optionKey))

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        var status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.hotkeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr, let handler else {
            print("hotkey: registration failed (OSStatus \(status))")
            return
        }
        eventHandler = handler

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            print("hotkey: registration failed (OSStatus \(status))")
            RemoveEventHandler(handler)
            eventHandler = nil
            return
        }
        hotKeyRef = ref
        print("hotkey: registered \(Self.describe(keyCode: keyCode, modifiers: modifiers))")
    }

    /// Re-reads the UserDefaults keys and swaps the registration; called by
    /// SettingsStore after persisting a new combo.
    func reRegister() {
        unregister()
        register()
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    // MARK: - Carbon plumbing

    /// "twen" as a FourCharCode.
    private static let signature: OSType = "twen".utf8.reduce(0) { ($0 << 8) + OSType($1) }

    /// C callback; Carbon dispatches hotkey events on the main thread.
    private static let hotkeyCallback: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated { manager.pressed() }
        return noErr
    }

    private func pressed() {
        AppModel.shared.requestBreak()
    }

    // MARK: - Display

    /// Human-readable combo, e.g. "⌥⌘B". Also used by the settings UI.
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var combo = ""
        if modifiers & UInt32(controlKey) != 0 { combo += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { combo += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { combo += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { combo += "⌘" }
        combo += keyNames[Int(keyCode)] ?? "keyCode \(keyCode)"
        return combo
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "Return", kVK_Escape: "Esc", kVK_Tab: "Tab",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Minus: "-",
        kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]
}
