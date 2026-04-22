import AppKit
import SwiftUI

struct FixedWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize
    let titlebarHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfAvailable(from: nsView)
        }
    }

    private func configureWindowIfAvailable(from view: NSView) {
        guard let window = view.window else { return }

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
        configureTitlebarAccessory(for: window)
    }

    private func configureTitlebarAccessory(for window: NSWindow) {
        let accessoryHeight: CGFloat = 0

        if let existing = window.titlebarAccessoryViewControllers
            .compactMap({ $0 as? WindowToolbarAccessoryController })
            .first {
            existing.updateHeight(accessoryHeight)
        }

        window.titlebarSeparatorStyle = .none
        positionWindowButtons(in: window)
        for button in [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap({ $0 }) {
            button.isHidden = false
        }
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
}
