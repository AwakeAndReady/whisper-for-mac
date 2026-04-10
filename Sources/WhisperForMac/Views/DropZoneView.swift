import SwiftUI

struct DropZoneView: View {
    let onSelectFile: () -> Void
    let onDropFile: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)

            Text("Drop Audio or Video Here")
                .font(.title3.weight(.semibold))

            Text("Drag a single local file into the window, or choose one from Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose File", action: onSelectFile)
                .keyboardShortcut("o", modifiers: [.command])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.quaternary.opacity(isTargeted ? 0.95 : 0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
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
