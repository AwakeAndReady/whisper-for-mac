import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            backendTab
                .tabItem {
                    Label("Backend", systemImage: "server.rack")
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
            Section("Environment") {
                LabeledContent("Python") {
                    Text(appState.backendStatus.pythonPath ?? "Not Found")
                }
                LabeledContent("ffmpeg") {
                    Text(appState.backendStatus.ffmpegPath ?? "Not Found")
                }
                LabeledContent("Managed Environment") {
                    Text(appState.backendStatus.environmentPath ?? "Not Created")
                }
                LabeledContent("Status") {
                    Text(appState.backendStatus.environmentReady ? "Ready" : "Needs Setup")
                }
                if let error = appState.backendStatus.errorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                if !appState.backendSetupMessage.isEmpty {
                    Text(appState.backendSetupMessage)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(appState.backendStatus.environmentReady ? "Repair Environment" : "Install Environment") {
                        appState.setupBackendEnvironment()
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
                            .disabled(!appState.backendStatus.environmentReady)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Models are stored inside the app support folder managed by Whisper for Mac.")
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
