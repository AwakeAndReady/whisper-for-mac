import AppKit
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case models
    case output
    case engine

    var title: String {
        switch self {
        case .models:
            return "Models"
        case .output:
            return "Output"
        case .engine:
            return "Engine"
        }
    }

    var systemImageName: String {
        switch self {
        case .models:
            return "square.stack.3d.down.forward"
        case .output:
            return "folder"
        case .engine:
            return "server.rack"
        }
    }
}

final class SettingsTabViewController: NSTabViewController {
    private let engineController = NSHostingController(rootView: AnyView(EmptyView()))
    private let modelsController = NSHostingController(rootView: AnyView(EmptyView()))
    private let outputController = NSHostingController(rootView: AnyView(EmptyView()))

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        preferredContentSize = NSSize(width: 700, height: 560)
        addTabItem(for: .models, controller: modelsController)
        addTabItem(for: .output, controller: outputController)
        addTabItem(for: .engine, controller: engineController)
    }

    func update(appState: AppState) {
        engineController.rootView = AnyView(
            EngineSettingsPane()
                .environmentObject(appState)
        )
        modelsController.rootView = AnyView(
            ModelsSettingsPane()
                .environmentObject(appState)
        )
        outputController.rootView = AnyView(
            OutputSettingsPane()
                .environmentObject(appState)
        )

        if tabViewItems.indices.contains(appState.settingsTab.rawValue),
           selectedTabViewItemIndex != appState.settingsTab.rawValue {
            selectedTabViewItemIndex = appState.settingsTab.rawValue
        }
    }

    private func addTabItem(for tab: SettingsTab, controller: NSHostingController<AnyView>) {
        let item = NSTabViewItem(viewController: controller)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.systemImageName, accessibilityDescription: tab.title)
        addTabViewItem(item)
    }
}

struct SettingsTabViewControllerRepresentable: NSViewControllerRepresentable {
    @ObservedObject var appState: AppState

    func makeNSViewController(context: Context) -> SettingsTabViewController {
        let controller = SettingsTabViewController()
        controller.loadViewIfNeeded()
        controller.update(appState: appState)
        return controller
    }

    func updateNSViewController(_ nsViewController: SettingsTabViewController, context: Context) {
        nsViewController.update(appState: appState)
    }
}
