import AppKit
import SwiftUI

struct QueueProgressView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                if appState.jobState.isBusy {
                    if appState.isCancellationPending {
                        Text("Waiting for the current operation to stop.")
                            .font(.callout).foregroundStyle(.secondary)
                        ProgressView()
                    } else {
                        Text(appState.jobState.progressDescription)
                            .font(.callout).foregroundStyle(.secondary)
                        if case let .running(_, fraction) = appState.jobState, let fraction {
                            ProgressView(value: fraction)
                        } else { ProgressView() }
                        Button("Stop Queue", role: .destructive) { appState.cancelTranscription() }
                    }
                } else {
                    Text("\(appState.finishedQueueCount) finished · \(appState.failedQueueCount) failed")
                        .font(.callout).foregroundStyle(.secondary)
                    if appState.jobState == .cancelled {
                        Text("Finished results are kept. Retry Unfinished processes the remaining files.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            ForEach(appState.queueItems) { item in
                queueRow(item)
                if item.id != appState.queueItems.last?.id { Divider() }
            }
        }
    }

    private var title: String {
        if appState.isCancellationPending { return "Stopping queue" }
        if let position = appState.currentQueuePosition, appState.jobState.isBusy {
            return "File \(position) of \(appState.queueItems.count)"
        }
        return appState.jobState == .cancelled ? "Queue stopped" : "Queue finished"
    }

    private func queueRow(_ item: TranscriptionQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.status.symbol)
                    .foregroundStyle(statusColor(item.status))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.inputURL.lastPathComponent)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1).truncationMode(.middle).help(item.inputURL.path)
                    Text(item.status.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if item.status == .succeeded {
                    TranscriptCopyButton(isEnabled: !item.transcriptText.isEmpty) {
                        appState.copyQueueTranscript(item.id)
                    }
                    .id(item.id)
                }
            }
            if item.status == .succeeded {
                HStack(spacing: 12) {
                    Button("Open") {
                        if let url = item.preferredOutputURL { NSWorkspace.shared.open(url) }
                    }
                    .disabled(item.preferredOutputURL == nil)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(item.outputURLs)
                    }
                    .disabled(item.outputURLs.isEmpty)
                    Text(item.outputURLs.map { $0.pathExtension.uppercased() }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 24)
            }
            if let message = item.errorMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            }
        }
    }

    private func statusColor(_ status: TranscriptionQueueItem.Status) -> Color {
        switch status {
        case .succeeded: Color(nsColor: .systemGreen)
        case .failed: .orange
        case .processing: .accentColor
        default: .secondary
        }
    }
}

struct QueueCompletionActions: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack {
            Button("Choose Other Files") { appState.chooseAnotherFile() }
                .buttonStyle(.borderless)
            Spacer()
            if appState.canStartTranscription {
                Button(appState.jobState == .cancelled ? "Retry Unfinished" : "Retry Failed") {
                    appState.runTranscription()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
