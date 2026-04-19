import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsTabViewControllerRepresentable(appState: appState)
            .frame(width: 700, height: 560)
    }
}
