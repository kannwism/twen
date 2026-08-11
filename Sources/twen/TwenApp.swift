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
        AppModel.shared.start()
    }
}
