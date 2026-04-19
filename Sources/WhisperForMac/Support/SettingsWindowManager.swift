import AppKit
import SwiftUI

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var windowController: NSWindowController?

    private init() {}

    func show(tab: SettingsTab, appState: AppState) {
        appState.settingsTab = tab

        let hostingController: NSHostingController<AnyView>
        if let existingHostingController = windowController?.contentViewController as? NSHostingController<AnyView> {
            hostingController = existingHostingController
        } else {
            hostingController = NSHostingController(rootView: AnyView(EmptyView()))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.setContentSize(NSSize(width: 700, height: 560))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = true
            windowController = controller
        }

        hostingController.rootView = AnyView(
            SettingsView()
                .environmentObject(appState)
                .frame(width: 700, height: 560)
        )

        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
