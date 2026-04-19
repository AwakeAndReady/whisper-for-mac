import SwiftUI

struct ModelsSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
                            HStack(spacing: 10) {
                                Text("Size: \(model.sizeText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if model.shouldShowSourceLink {
                                    Link(model.sourceLabel, destination: model.sourceURL)
                                        .font(.caption)
                                        .help(model.sourceURL.absoluteString)
                                }
                            }
                        }
                        Spacer()
                        modelActions(for: model)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Models are downloaded on demand from the official whisper.cpp Hugging Face repository and stored locally in Whisper for Mac's Application Support folder.")
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func installActivityIndicator(for model: WhisperModelInfo) -> some View {
        Group {
            if let progress = model.installProgressFraction {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
            } else {
                SwiftUI.ProgressView()
            }
        }
        .controlSize(.small)
        .help(model.installProgressAccessibilityText ?? "Downloading \(model.displayName)")
    }

    private func modelActions(for model: WhisperModelInfo) -> some View {
        HStack(spacing: 8) {
            if model.installState.isRemoving {
                SwiftUI.ProgressView()
                    .controlSize(.small)
            } else if model.shouldShowInstallProgressIndicator {
                installActivityIndicator(for: model)
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }

            if model.isInstalled {
                Button("Remove") {
                    appState.removeModel(model.id)
                }
                .disabled(model.installState.isRemoving)
            } else {
                Button("Install") {
                    appState.installModel(model.id)
                }
                .disabled(!appState.backendStatus.engineReady || model.installState.isInstalling)
            }
        }
        .frame(width: 110, alignment: .trailing)
    }
}
