import SwiftUI

private enum ProgressStage: CaseIterable {
    case preparing
    case transcribing
    case writing
    case done

    var title: String {
        switch self {
        case .preparing:
            return "Preparing"
        case .transcribing:
            return "Transcribing"
        case .writing:
            return "Writing Files"
        case .done:
            return "Done"
        }
    }
}

struct JobProgressSection: View {
    @EnvironmentObject private var appState: AppState

    let onOpenModelSettings: () -> Void

    @State private var displayedProgress = TranscriptionProgressDisplayState()

    private let progressSmoother = TranscriptionProgressSmoother()
    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stageStrip

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

    private var stageStrip: some View {
        HStack(spacing: 12) {
            ForEach(ProgressStage.allCases, id: \.title) { stage in
                HStack(spacing: 8) {
                    Image(systemName: symbolName(for: stage))
                        .foregroundStyle(color(for: stage))
                    Text(stage.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(color(for: stage))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color(for: stage).opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.35))
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.35))
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

                Button("Transcribe Another File") {
                    appState.chooseAnotherFile()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .systemGreen).opacity(0.035))
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
                } else if appState.installedModelCount == 0 {
                    Button("Manage Models", action: onOpenModelSettings)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Choose Another File") {
                        appState.chooseAnotherFile()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.selectedFileURL != nil {
                    Button("Choose Another File") {
                        appState.chooseAnotherFile()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private func symbolName(for stage: ProgressStage) -> String {
        switch stageStatus(for: stage) {
        case .done:
            return "checkmark.circle.fill"
        case .active:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .pending:
            return "circle"
        }
    }

    private func color(for stage: ProgressStage) -> Color {
        switch stageStatus(for: stage) {
        case .done:
            return Color(nsColor: .systemGreen)
        case .active:
            return .accentColor
        case .pending:
            return .secondary
        }
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

    private func stageStatus(for stage: ProgressStage) -> StageStatus {
        switch appState.jobState {
        case .idle, .awaitingConfirmation, .failed:
            return .pending
        case .preparing:
            return stage == .preparing ? .active : .pending
        case .running:
            if stage == .preparing {
                return .done
            }
            return stage == .transcribing ? .active : .pending
        case .writingOutputs:
            if stage == .done {
                return .pending
            }
            return stage == .writing ? .active : .done
        case .succeeded:
            return .done
        }
    }
}

private enum StageStatus {
    case pending
    case active
    case done
}
