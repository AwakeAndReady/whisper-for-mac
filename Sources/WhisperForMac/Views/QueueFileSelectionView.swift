import SwiftUI

struct QueueFileSelectionView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        optionsSection(title: "Files", detail: "\(appState.queueItems.count) selected · Processed in this order") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(appState.queueItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "waveform").foregroundStyle(.secondary)
                        Text(item.inputURL.lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                            .help(item.inputURL.path)
                        Spacer(minLength: 0)
                        Button { appState.removeQueuedFile(item.id) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(item.inputURL.lastPathComponent)")
                        .accessibilityLabel("Remove \(item.inputURL.lastPathComponent)")
                    }
                }
                Divider()
                HStack {
                    Button("Add Files…") { appState.showFileImporter = true }
                    Spacer()
                    Button("Clear") { appState.chooseAnotherFile() }
                }
                .buttonStyle(.borderless)
                if let error = appState.transientErrorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            appState.chooseFiles(urls, appending: true)
        }
    }
}
