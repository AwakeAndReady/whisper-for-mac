import SwiftUI

struct TranscriptCopyButton: View {
    let isEnabled: Bool
    let onCopy: () -> Bool

    @State private var feedback: Bool?
    @State private var feedbackGeneration = 0

    var body: some View {
        HStack(spacing: 6) {
            if let feedback {
                Text(feedback ? "Copied" : "Copy failed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Button {
                feedback = onCopy()
                feedbackGeneration += 1
            } label: {
                Image(systemName: symbolName)
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(!isEnabled)
            .help("Copy Transcript")
            .accessibilityLabel(accessibilityLabel)
        }
        .task(id: feedbackGeneration) {
            guard feedback != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                feedback = nil
            } catch { }
        }
    }

    private var symbolName: String {
        switch feedback {
        case true: "checkmark"
        case false: "exclamationmark.triangle"
        case nil: "doc.on.doc"
        }
    }

    private var accessibilityLabel: String {
        switch feedback {
        case true: "Transcript copied. Copy again"
        case false: "Copy failed. Try again"
        case nil: "Copy Transcript"
        }
    }
}
