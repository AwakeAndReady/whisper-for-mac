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
                    appDelegate.appState = appState
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var terminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        if appState.jobState.isBusy {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Quit Whisper for Mac?"
            alert.informativeText = "A transcription is still in progress. Quitting will cancel it, and unfinished output may be lost."
            let keepTranscribingButton = alert.addButton(withTitle: "Keep Transcribing")
            keepTranscribingButton.keyEquivalent = "\u{1B}"
            alert.addButton(withTitle: "Quit and Cancel Transcription")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }

        appState.beginShutdown()
        terminationTask = Task {
            await appState.finishShutdown()
            sender.reply(toApplicationShouldTerminate: true)
            terminationTask = nil
        }
        return .terminateLater
    }
}
