import SwiftUI

struct DropZoneView: View {
    let onSelectFile: () -> Void
    let onDropFile: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text("Add an audio or video file")
                .font(.title3.weight(.semibold))

            Text("Drag a single local file into the window, or choose one from Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose File", action: onSelectFile)
                .buttonStyle(.bordered)
                .keyboardShortcut("o", modifiers: [.command])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WizardChrome.controlBackground.opacity(isTargeted ? 1 : 0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.32),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                        )
                }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            onDropFile(first)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}
