import AppKit
import SwiftUI

final class WizardSplitViewController: NSSplitViewController {
    private let sidebarController = TransparentHostingController(rootView: AnyView(EmptyView()))
    private let contentController = TransparentHostingController(rootView: AnyView(EmptyView()))

    private let sidebarItem: NSSplitViewItem
    private let contentItem: NSSplitViewItem
    private let sidebarWidth: CGFloat

    init(sidebarWidth: CGFloat) {
        self.sidebarWidth = sidebarWidth
        self.sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        self.contentItem = NSSplitViewItem(viewController: contentController)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = sidebarWidth
        sidebarItem.maximumThickness = sidebarWidth
        sidebarItem.allowsFullHeightLayout = true

        contentItem.canCollapse = false
        contentItem.allowsFullHeightLayout = true

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    func update(sidebar: AnyView, content: AnyView) {
        sidebarController.rootView = sidebar
        contentController.rootView = content
    }
}

private final class TransparentHostingController: NSHostingController<AnyView> {
    override func loadView() {
        super.loadView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

struct WizardSplitViewControllerRepresentable: NSViewControllerRepresentable {
    let sidebarWidth: CGFloat
    let sidebar: AnyView
    let content: AnyView

    func makeNSViewController(context: Context) -> WizardSplitViewController {
        let controller = WizardSplitViewController(sidebarWidth: sidebarWidth)
        controller.loadViewIfNeeded()
        controller.update(sidebar: sidebar, content: content)
        return controller
    }

    func updateNSViewController(_ nsViewController: WizardSplitViewController, context: Context) {
        nsViewController.update(sidebar: sidebar, content: content)
    }
}
