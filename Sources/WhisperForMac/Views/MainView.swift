import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                DropZoneView(
                    onSelectFile: { appState.showFileImporter = true },
                    onDropFile: { appState.chooseFile($0) }
                )

                if let error = appState.transientErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let fileURL = appState.selectedFileURL {
                    fileSummary(fileURL)
                }

                TranscriptionOptionsView()
                JobProgressSection(
                    state: appState.jobState,
                    onCancel: { appState.cancelTranscription() },
                    onRevealOutputs: {
                        guard !appState.lastOutputURLs.isEmpty else { return }
                        NSWorkspace.shared.activateFileViewerSelecting(appState.lastOutputURLs)
                    }
                )

                footerActions
            }
            .padding(24)
        }
        .navigationTitle("Whisper for Mac")
        .toolbar {
            ToolbarItemGroup {
                Button("Choose File") {
                    appState.showFileImporter = true
                }

                Button("Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        .fileImporter(
            isPresented: $appState.showFileImporter,
            allowedContentTypes: MediaFileValidator.importTypes,
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.chooseFile(url)
            }
        }
        .sheet(isPresented: $appState.showConfirmationSheet) {
            ConfirmationSheetView()
                .environmentObject(appState)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Whisper Transcription")
                .font(.largeTitle.weight(.bold))
            Text("Transcribe or translate audio and video files on this Mac using a managed local Whisper environment.")
                .foregroundStyle(.secondary)
        }
    }

    private func fileSummary(_ url: URL) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("File")
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                }
                GridRow {
                    Text("Location")
                        .foregroundStyle(.secondary)
                    Text(url.path)
                        .lineLimit(2)
                }
                GridRow {
                    Text("Media Type")
                        .foregroundStyle(.secondary)
                    Text(url.pathExtension.uppercased())
                }
                GridRow {
                    Text("Backend")
                        .foregroundStyle(.secondary)
                    Text(appState.backendStatus.environmentReady ? "Ready" : "Needs Setup")
                }
            }
        } label: {
            Text("Selected File")
        }
    }

    private var footerActions: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.backendStatus.environmentReady ? "Managed backend ready" : "Managed backend not ready")
                    .font(.subheadline.weight(.medium))
                Text(appState.backendStatus.errorMessage ?? appState.backendSetupMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Start Transcription") {
                appState.showConfirmation()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(appState.selectedFileURL == nil || appState.selectedFileError != nil || appState.jobState.isBusy)
        }
    }
}
