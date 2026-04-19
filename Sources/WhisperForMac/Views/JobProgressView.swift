import SwiftUI

struct JobProgressSection: View {
    let state: TranscriptionJobState
    let onCancel: () -> Void
    let onRevealOutputs: () -> Void

    @State private var displayedProgress = TranscriptionProgressDisplayState()

    private let progressSmoother = TranscriptionProgressSmoother()
    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .idle, .awaitingConfirmation:
                    Label("No active transcription", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                case .preparing:
                    progressRow("Preparing backend", fraction: displayedProgress.displayedFraction)
                case let .running(text, fraction):
                    progressRow(text, fraction: displayedFraction(fallingBackTo: fraction))
                case .writingOutputs:
                    progressRow("Writing output files", fraction: displayedFraction(fallingBackTo: 0.95))
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
        .onAppear {
            refreshDisplayedProgress(at: Date())
        }
        .onChange(of: state) { _, _ in
            refreshDisplayedProgress(at: Date())
        }
        .onReceive(progressTimer) { now in
            guard state.isBusy else { return }
            refreshDisplayedProgress(at: now)
        }
    }

    @ViewBuilder
    private func progressRow(_ title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if let fraction {
                SwiftUI.ProgressView(value: fraction, total: 1)
                    .animation(.linear(duration: 0.12), value: fraction)
            } else {
                SwiftUI.ProgressView()
                    .controlSize(.regular)
            }
        }
    }

    private func displayedFraction(fallingBackTo fallback: Double?) -> Double? {
        displayedProgress.displayedFraction ?? fallback
    }

    private func refreshDisplayedProgress(at now: Date) {
        displayedProgress = progressSmoother.updatedState(for: state, at: now, previous: displayedProgress)
    }
}
