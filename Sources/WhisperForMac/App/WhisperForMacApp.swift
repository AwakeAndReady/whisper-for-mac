import AppKit
import SwiftUI

@main
struct WhisperForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Whisper for Mac") {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 820, minHeight: 700)
                .task {
                    await appState.initialize()
                }
        }
        .defaultSize(width: 920, height: 760)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 700, height: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
