import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            backendTab
                .tabItem {
                    Label("Engine", systemImage: "server.rack")
                }

            modelsTab
                .tabItem {
                    Label("Models", systemImage: "square.stack.3d.down.forward")
                }

            outputTab
                .tabItem {
                    Label("Output", systemImage: "folder")
                }
        }
        .padding(20)
    }

    private var backendTab: some View {
        Form {
            Section("Engine") {
                LabeledContent("Runtime") {
                    Text("Native whisper.cpp")
                }
                LabeledContent("Version") {
                    Text(appState.backendStatus.engineVersion ?? "Unavailable")
                }
                LabeledContent("Model Store") {
                    Text(appState.backendStatus.modelStorePath ?? "Unavailable")
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Status") {
                    Text(appState.backendStatus.engineReady ? "Ready" : "Unavailable")
                }
                LabeledContent("Installed Models") {
                    Text("\(appState.installedModelCount)")
                }
                if !appState.backendStatus.installedModelsAvailable {
                    Text("No model is bundled with the app. Download the model you want in the Models tab before the first transcription.")
                        .foregroundStyle(.secondary)
                }
                if let error = appState.backendStatus.errorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Models Folder") {
                        guard let modelStorePath = appState.backendStatus.modelStorePath else { return }
                        NSWorkspace.shared.open(URL(fileURLWithPath: modelStorePath))
                    }
                    Button("Refresh Status") {
                        Task {
                            await appState.refreshBackendStatus()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var modelsTab: some View {
        List {
            Section {
                ForEach(appState.models) { model in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.headline)
                            Text(model.statusText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(model.capabilitySummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let localSizeBytes = model.localSizeBytes {
                                Text(ByteCountFormatter.string(fromByteCount: localSizeBytes, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.installState == .installing || model.installState == .removing {
                            SwiftUI.ProgressView()
                                .controlSize(.small)
                        }
                        if model.isInstalled {
                            Button("Remove") {
                                appState.removeModel(model.id)
                            }
                        } else {
                            Button("Install") {
                                appState.installModel(model.id)
                            }
                            .disabled(!appState.backendStatus.engineReady)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Models are downloaded on demand and stored in the app support folder managed by Whisper for Mac.")
            }
        }
    }

    private var outputTab: some View {
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
