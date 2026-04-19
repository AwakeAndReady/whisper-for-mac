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
                .frame(minWidth: 700, minHeight: 600)
                .task {
                    await appState.initialize()
                }
        }
        .defaultSize(width: 780, height: 650)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appState.presentSettings(tab: .models)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
