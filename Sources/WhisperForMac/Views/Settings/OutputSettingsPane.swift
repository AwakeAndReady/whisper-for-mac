import AppKit
import SwiftUI

struct OutputSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Default Output") {
                Picker("Folder Rule", selection: binding(for: \.outputLocationMode)) {
                    Text("Next to source file").tag(OutputLocationMode.nextToSource)
                    Text("Custom folder").tag(OutputLocationMode.custom)
                }

                LabeledContent("Custom Folder") {
                    Text(appState.preferences.customOutputDirectory?.path ?? "Not Set")
                }

                Button("Choose Custom Folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.setCustomOutputDirectory(url)
                    }
                }

                Toggle("TXT transcript", isOn: outputBinding(for: .txt))
                Toggle("VTT subtitles", isOn: outputBinding(for: .vtt))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding<Value>(for keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.preferences[keyPath: keyPath] },
            set: { newValue in
                appState.preferences[keyPath: keyPath] = newValue
                appState.savePreferences()
            }
        )
    }

    private func outputBinding(for format: OutputFormat) -> Binding<Bool> {
        Binding(
            get: {
                appState.preferences.outputFormats.contains(format)
            },
            set: { enabled in
                if enabled {
                    appState.preferences.outputFormats.insert(format)
                } else if appState.preferences.outputFormats.count > 1 {
                    appState.preferences.outputFormats.remove(format)
                }
                appState.savePreferences()
            }
        )
    }
}
