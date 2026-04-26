import AppKit
import SwiftUI

struct FixedWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize
    let titlebarHeight: CGFloat
    let sidebarWidth: CGFloat
    @Binding var isWindowActive: Bool
    let onOpenSettings: () -> Void
    let onOpenHelp: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isWindowActive: $isWindowActive,
            onOpenSettings: onOpenSettings,
            onOpenHelp: onOpenHelp
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(onOpenSettings: onOpenSettings, onOpenHelp: onOpenHelp)
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindowIfAvailable(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        let splitView = window.contentView?.firstDescendant(of: NSSplitView.self)
        coordinator.observe(window: window)

        let size = NSSize(width: contentSize.width, height: contentSize.height)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        installOrUpdateTitlebarChrome(in: window, splitView: splitView)
        installOrUpdateToolbar(in: window, splitView: splitView, coordinator: coordinator)
        positionWindowButtons(in: window)

        if splitView == nil, coordinator.shouldRetrySplitViewLookup() {
            DispatchQueue.main.async {
                configureWindowIfAvailable(from: view, coordinator: coordinator)
            }
        } else if splitView != nil {
            coordinator.resetSplitViewLookupRetry()
        }
    }

    private func installOrUpdateTitlebarChrome(in window: NSWindow, splitView: NSSplitView?) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarContainer = closeButton.superview
        else { return }

        if let chromeView = titlebarContainer.subviews.first(where: {
            $0.identifier == .windowTitlebarChrome
        }) as? WindowTitlebarChromeView {
            chromeView.frame = titlebarChromeFrame(in: titlebarContainer)
            chromeView.update(sidebarWidth: sidebarWidth, splitView: splitView)
            positionChromeView(chromeView, in: titlebarContainer)
            return
        }

        let chromeView = WindowTitlebarChromeView(sidebarWidth: sidebarWidth)
        chromeView.identifier = .windowTitlebarChrome
        chromeView.frame = titlebarChromeFrame(in: titlebarContainer)
        chromeView.update(sidebarWidth: sidebarWidth, splitView: splitView)
        positionChromeView(chromeView, in: titlebarContainer)
    }

    private func positionChromeView(_ chromeView: NSView, in titlebarContainer: NSView) {
        if let backmostSubview = titlebarContainer.subviews.first {
            titlebarContainer.addSubview(chromeView, positioned: .below, relativeTo: backmostSubview)
        } else {
            titlebarContainer.addSubview(chromeView)
        }
    }

    private func titlebarChromeFrame(in titlebarContainer: NSView) -> NSRect {
        NSRect(
            x: 0,
            y: max(0, titlebarContainer.bounds.height - titlebarHeight),
            width: titlebarContainer.bounds.width,
            height: titlebarHeight
        )
    }

    private func installOrUpdateToolbar(
        in window: NSWindow,
        splitView: NSSplitView?,
        coordinator: Coordinator
    ) {
        guard let splitView else { return }

        coordinator.update(splitView: splitView)

        if let toolbar = window.toolbar,
           toolbar.identifier == .wizardWindowToolbar,
           coordinator.toolbarSplitView === splitView {
            toolbar.delegate = coordinator
            return
        }

        let toolbar = NSToolbar(identifier: .wizardWindowToolbar)
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = coordinator
        window.toolbar = toolbar
    }

    private func positionWindowButtons(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }

        guard buttons.count == 3 else { return }

        let leftInset: CGFloat = 14
        let interButtonSpacing: CGFloat = 8
        let targetY: CGFloat = 18

        var currentX = leftInset
        for button in buttons {
            var frame = button.frame
            frame.origin.x = currentX
            frame.origin.y = targetY
            button.setFrameOrigin(frame.origin)
            currentX += frame.width + interButtonSpacing
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        @Binding private var isWindowActive: Bool
        private var onOpenSettings: () -> Void
        private var onOpenHelp: () -> Void
        private var splitViewLookupRetryCount = 0
        private weak var observedWindow: NSWindow?
        weak var toolbarSplitView: NSSplitView?

        init(
            isWindowActive: Binding<Bool>,
            onOpenSettings: @escaping () -> Void,
            onOpenHelp: @escaping () -> Void
        ) {
            _isWindowActive = isWindowActive
            self.onOpenSettings = onOpenSettings
            self.onOpenHelp = onOpenHelp
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func update(onOpenSettings: @escaping () -> Void, onOpenHelp: @escaping () -> Void) {
            self.onOpenSettings = onOpenSettings
            self.onOpenHelp = onOpenHelp
        }

        func observe(window: NSWindow) {
            guard observedWindow !== window else {
                isWindowActive = window.isKeyWindow
                return
            }

            NotificationCenter.default.removeObserver(self)
            observedWindow = window
            isWindowActive = window.isKeyWindow

            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            center.addObserver(
                self,
                selector: #selector(windowDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        }

        func update(splitView: NSSplitView) {
            toolbarSplitView = splitView
        }

        func shouldRetrySplitViewLookup() -> Bool {
            guard splitViewLookupRetryCount < 8 else { return false }
            splitViewLookupRetryCount += 1
            return true
        }

        func resetSplitViewLookupRetry() {
            splitViewLookupRetryCount = 0
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [
                .flexibleSpace,
                .wizardSettings,
                .wizardHelp,
            ]
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [
                .flexibleSpace,
                .wizardSettings,
                .wizardHelp,
            ]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            switch itemIdentifier {
            case .wizardSettings:
                return toolbarButton(
                    identifier: itemIdentifier,
                    label: "Settings",
                    systemSymbolName: "gearshape",
                    action: #selector(openSettings)
                )
            case .wizardHelp:
                return toolbarButton(
                    identifier: itemIdentifier,
                    label: "Help",
                    systemSymbolName: "questionmark.circle",
                    action: #selector(openHelp)
                )
            default:
                return nil
            }
        }

        private func toolbarButton(
            identifier: NSToolbarItem.Identifier,
            label: String,
            systemSymbolName: String,
            action: Selector
        ) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.image = NSImage(
                systemSymbolName: systemSymbolName,
                accessibilityDescription: label
            )
            item.target = self
            item.action = action
            return item
        }

        @objc
        private func openSettings() {
            onOpenSettings()
        }

        @objc
        private func openHelp() {
            onOpenHelp()
        }

        @objc
        private func windowDidBecomeKey() {
            isWindowActive = true
        }

        @objc
        private func windowDidResignKey() {
            isWindowActive = false
        }
    }
}

private extension NSView {
    func firstDescendant<View: NSView>(of type: View.Type) -> View? {
        if let view = self as? View {
            return view
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}

private extension NSToolbar.Identifier {
    static let wizardWindowToolbar = NSToolbar.Identifier("WizardWindowToolbar")
}

private extension NSToolbarItem.Identifier {
    static let wizardSettings = NSToolbarItem.Identifier("WizardSettings")
    static let wizardHelp = NSToolbarItem.Identifier("WizardHelp")
}
