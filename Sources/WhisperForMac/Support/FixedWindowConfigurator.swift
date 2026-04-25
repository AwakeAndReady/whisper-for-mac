import AppKit
import SwiftUI

struct FixedWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize
    let titlebarHeight: CGFloat
    let sidebarWidth: CGFloat
    @Binding var isWindowActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isWindowActive: $isWindowActive)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindowIfAvailable(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

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
        configureTitlebarChrome(for: window)
    }

    private func configureTitlebarChrome(for window: NSWindow) {
        window.titlebarSeparatorStyle = .none
        installOrUpdateTitlebarChrome(in: window)
        positionWindowButtons(in: window)

        for button in [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap({ $0 }) {
            button.isHidden = false
        }
    }

    private func installOrUpdateTitlebarChrome(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarContainer = closeButton.superview
        else { return }

        if let chromeView = titlebarContainer.subviews.first(where: {
            $0.identifier == .windowTitlebarChrome
        }) as? WindowTitlebarChromeView {
            chromeView.frame = titlebarContainer.bounds
            chromeView.update(sidebarWidth: sidebarWidth, isWindowActive: window.isKeyWindow)
            titlebarContainer.addSubview(chromeView, positioned: .below, relativeTo: closeButton)
            return
        }

        let chromeView = WindowTitlebarChromeView(sidebarWidth: sidebarWidth, isWindowActive: window.isKeyWindow)
        chromeView.identifier = .windowTitlebarChrome
        chromeView.frame = titlebarContainer.bounds
        titlebarContainer.addSubview(chromeView, positioned: .below, relativeTo: closeButton)
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
    final class Coordinator: NSObject {
        @Binding private var isWindowActive: Bool

        private weak var observedWindow: NSWindow?

        init(isWindowActive: Binding<Bool>) {
            _isWindowActive = isWindowActive
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
