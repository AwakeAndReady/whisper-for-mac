import SwiftUI

struct JobProgressSection: View {
    let state: TranscriptionJobState
    let onCancel: () -> Void
    let onRevealOutputs: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .idle, .awaitingConfirmation:
                    Label("No active transcription", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                case .preparing:
                    progressRow("Preparing backend", fraction: 0.08)
                case let .running(text, fraction):
                    progressRow(text, fraction: fraction)
                case .writingOutputs:
                    progressRow("Writing output files", fraction: 0.95)
                case .succeeded:
                    Label("Transcription finished successfully.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Reveal Output Files", action: onRevealOutputs)
                case let .failed(message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                if state.isBusy {
                    Button("Cancel", role: .destructive, action: onCancel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Progress")
        }
    }

    @ViewBuilder
    private func progressRow(_ title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if let fraction {
                SwiftUI.ProgressView(value: fraction, total: 1)
            } else {
                SwiftUI.ProgressView()
                    .controlSize(.regular)
            }
        }
    }
}
