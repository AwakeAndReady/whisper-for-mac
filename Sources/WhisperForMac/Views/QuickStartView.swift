import SwiftUI

struct QuickStartView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        optionsSection(
            title: "Quick Start",
            detail: "Review your settings, then start or change them."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if appState.isQueue {
                    Label("\(appState.queueItems.count) files · Same settings for all", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                    Button("Review Files") { appState.wizardStep = .file }
                        .buttonStyle(.borderless)
                } else if let fileURL = appState.selectedFileURL {
                    Label(fileURL.lastPathComponent, systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(fileURL.path)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    summaryRow("Model", value: appState.selectedInstalledModelInfo?.displayName ?? "Unavailable")
                    summaryRow("Language", value: LanguageCatalog.displayName(for: appState.selectedLanguageCode))
                    summaryRow("Task", value: appState.selectedTask.title)
                    summaryRow("Formats", value: appState.outputFormatsSummary)
                    summaryRow("Save To", value: appState.outputLocationSummary)
                    summaryRow("Core ML", value: coreMLSummary)
                }
                .font(.callout)

                if let issue = appState.quickStartConfigurationIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = appState.transientErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(appState.isQueue ? "Choose Other Files" : "Choose Another File") {
                    appState.chooseAnotherFile()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var coreMLSummary: String {
        if appState.shouldUseCoreMLForSelectedModel { return "On" }
        if appState.preferences.useCoreMLAcceleration { return "Unavailable for this model or Mac" }
        return "Off"
    }
}
