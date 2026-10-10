import SwiftUI

struct DropZoneView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onSelectFile: () -> Void
    let onDropFiles: ([URL]) -> Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text("Add audio or video files")
                .font(.title3.weight(.semibold))

            Text("Drag local files into the window, or choose them from Finder. Multiple files run one after another.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose Files", action: onSelectFile)
                .buttonStyle(.bordered)
                .keyboardShortcut("o", modifiers: [.command])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WizardChrome.palette(for: colorScheme).controlBackground.opacity(isTargeted ? 1 : 0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor.opacity(0.7) : WizardChrome.palette(for: colorScheme).separator.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                        )
                }
        }
        .dropDestination(for: URL.self) { urls, _ in
            onDropFiles(urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}
