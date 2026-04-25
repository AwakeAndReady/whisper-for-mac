import SwiftUI

struct JobProgressSection: View {
    @EnvironmentObject private var appState: AppState

    let onOpenModelSettings: () -> Void

    @State private var displayedProgress = TranscriptionProgressDisplayState()

    private let progressSmoother = TranscriptionProgressSmoother()
    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch appState.jobState {
            case .idle, .awaitingConfirmation:
                idleState
            case .preparing:
                runningState(title: "Preparing the backend", detail: "Checking the model and extracting audio samples.")
            case let .running(text, fraction):
                runningState(
                    title: "Transcribing audio",
                    detail: text,
                    fraction: displayedFraction(fallingBackTo: fraction)
                )
            case .writingOutputs:
                runningState(
                    title: "Writing output files",
                    detail: "Saving the transcript and subtitle files to disk.",
                    fraction: displayedFraction(fallingBackTo: 0.95)
                )
            case .succeeded:
                successState
            case let .failed(message):
                errorState(message: message)
            }
        }
        .onAppear {
            refreshDisplayedProgress(at: Date())
        }
        .onChange(of: appState.jobState) { _, _ in
            refreshDisplayedProgress(at: Date())
        }
        .onReceive(progressTimer) { now in
            guard appState.jobState.isBusy else { return }
            refreshDisplayedProgress(at: now)
        }
    }

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No transcription is running right now.")
                .font(.headline)
            Text("Once you start a job, the current stage and the finished output files will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 0.66,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground
        )
    }

    private func runningState(title: String, detail: String, fraction: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let fraction {
                ProgressView(value: fraction, total: 1)
                    .animation(.linear(duration: 0.12), value: fraction)
            } else {
                ProgressView()
            }

            Button("Cancel", role: .destructive) {
                appState.cancelTranscription()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 0.66,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground
        )
    }

    private var successState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemGreen))

                Text("Transcript finished successfully.")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if !appState.lastOutputURLs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output files")
                        .font(.subheadline.weight(.semibold))

                    ForEach(appState.lastOutputURLs, id: \.path) { url in
                        Label(url.lastPathComponent, systemImage: outputSymbol(for: url))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Open Transcript") {
                    appState.openPreferredOutput()
                }
                .disabled(appState.preferredOutputURL == nil)

                Button("Reveal in Finder") {
                    appState.revealOutputsInFinder()
                }
                .disabled(appState.lastOutputURLs.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 0.66,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground,
            tint: Color(nsColor: .systemGreen),
            tintOpacity: 0.035
        )
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The last transcription did not complete.", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if appState.canStartTranscription {
                    Button("Try Again") {
                        appState.runTranscription()
                    }
                    .buttonStyle(.borderedProminent)

                    if appState.selectedFileURL != nil {
                        Button("Choose Another File") {
                            appState.chooseAnotherFile()
                        }
                        .buttonStyle(.borderless)
                    }
                } else if appState.installedModelCount == 0 {
                    Button("Manage Models", action: onOpenModelSettings)
                        .buttonStyle(.borderedProminent)

                    if appState.selectedFileURL != nil {
                        Button("Choose Another File") {
                            appState.chooseAnotherFile()
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button("Choose Another File") {
                        appState.chooseAnotherFile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .whisperSurface(
            padding: 14,
            cornerRadius: WizardChrome.sectionCornerRadius,
            fillOpacity: 0.66,
            borderOpacity: 0.14,
            fillColor: WizardChrome.cardBackground,
            tint: .orange,
            tintOpacity: 0.04
        )
    }

    private func outputSymbol(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case OutputFormat.txt.rawValue:
            return "doc.text"
        case OutputFormat.vtt.rawValue:
            return "captions.bubble"
        default:
            return "doc"
        }
    }

    private func displayedFraction(fallingBackTo fallback: Double?) -> Double? {
        displayedProgress.displayedFraction ?? fallback
    }

    private func refreshDisplayedProgress(at now: Date) {
        displayedProgress = progressSmoother.updatedState(for: appState.jobState, at: now, previous: displayedProgress)
    }
}
