import SwiftUI
import AppKit

struct ModelsSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Advanced model management")
                                .font(.headline)
                            Text("Install or remove models here. Models are downloaded on demand from the official whisper.cpp Hugging Face repository.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            guard let modelStorePath = appState.backendStatus.modelStorePath else { return }
                            NSWorkspace.shared.open(URL(fileURLWithPath: modelStorePath))
                        } label: {
                            Label("Open Models Folder", systemImage: "folder")
                        }
                        .labelStyle(.titleAndIcon)
                        .disabled(appState.backendStatus.modelStorePath == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(appState.models) { model in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(model.displayName)
                                    .font(.headline)
                                if let highlightLabel = model.highlightLabel {
                                    Text(highlightLabel)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(model.statusText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(model.setupSummary)
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
