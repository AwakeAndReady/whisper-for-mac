import AppKit
import SwiftUI

private enum SettingsTab: CaseIterable {
    case engine
    case models
    case output

    var title: String {
        switch self {
        case .engine:
            return "Engine"
        case .models:
            return "Models"
        case .output:
            return "Output"
        }
    }

    var systemImageName: String {
        switch self {
        case .engine:
            return "server.rack"
        case .models:
            return "square.stack.3d.down.forward"
        case .output:
            return "folder"
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
        addTabItem(for: .engine, controller: engineController)
        addTabItem(for: .models, controller: modelsController)
        addTabItem(for: .output, controller: outputController)
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
        controller.update(appState: appState)
        return controller
    }

    func updateNSViewController(_ nsViewController: SettingsTabViewController, context: Context) {
        nsViewController.update(appState: appState)
    }
}
