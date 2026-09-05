import AppKit
import SwiftUI

@main
struct WhisperForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @State private var isWindowActive = true
    private let fixedWindowSize = CGSize(width: 680, height: 404)
    private let sidebarWidth: CGFloat = 190
    private let titlebarHeight: CGFloat = 54

    var body: some Scene {
        WindowGroup("Whisper for Mac") {
            MainView(isWindowActive: isWindowActive)
                .environmentObject(appState)
                .frame(width: fixedWindowSize.width, height: fixedWindowSize.height)
                .background {
                    FixedWindowConfigurator(
                        contentSize: fixedWindowSize,
                        titlebarHeight: titlebarHeight,
                        sidebarWidth: sidebarWidth,
                        isWindowActive: $isWindowActive,
                        onOpenSettings: {
                            appState.presentSettings(tab: .models)
                        },
                        onOpenHelp: {
                            guard let url = URL(string: "https://github.com/AwakeAndReady/whisper-for-mac") else { return }
                            NSWorkspace.shared.open(url)
                        }
                    )
                }
                .task {
                    await appState.initialize()
                }
        }
        .defaultSize(width: fixedWindowSize.width, height: fixedWindowSize.height)
        .windowResizability(.contentSize)
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
