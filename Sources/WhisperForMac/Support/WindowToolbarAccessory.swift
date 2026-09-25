import AppKit
import SwiftUI

final class WindowTitlebarChromeView: NSView {
    private let sidebarMaterialView = NSVisualEffectView()
    private let sidebarInactiveFillView = NSView()
    private let toolbarFillView = NSView()
    private let dividerView = NSView()
    private let toolbarBottomDividerView = NSView()

    private var sidebarWidth: CGFloat
    private var colorScheme: ColorScheme
    private weak var splitView: NSSplitView?

    init(sidebarWidth: CGFloat, colorScheme: ColorScheme) {
        self.sidebarWidth = sidebarWidth
        self.colorScheme = colorScheme
        super.init(frame: .zero)
        configureSubviews()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)

        guard let window else { return }

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowDidChangeKeyStatus),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeKeyStatus),
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        needsLayout = true
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()

        let rightX = min(bounds.width, max(0, contentStartX))
        let dividerWidth = WizardDividerStyle.pixelWidth(for: window)
        let dividerX = min(bounds.width - dividerWidth, max(0, rightX - (dividerWidth / 2)))

        sidebarMaterialView.frame = NSRect(x: 0, y: 0, width: rightX, height: bounds.height)
        sidebarInactiveFillView.frame = sidebarMaterialView.frame
        dividerView.frame = NSRect(x: dividerX, y: 0, width: dividerWidth, height: bounds.height)
        toolbarFillView.frame = NSRect(x: rightX, y: 0, width: max(0, bounds.width - rightX), height: bounds.height)
        toolbarBottomDividerView.frame = NSRect(
            x: rightX,
            y: 0,
            width: max(0, bounds.width - rightX),
            height: dividerWidth
        )
    }

    func update(sidebarWidth: CGFloat, splitView: NSSplitView?, colorScheme: ColorScheme) {
        self.sidebarWidth = sidebarWidth
        self.colorScheme = colorScheme
        self.splitView = splitView
        updateAppearance()
        needsLayout = true
    }

    private func configureSubviews() {
        autoresizingMask = [.width, .height]

        sidebarMaterialView.material = .sidebar
        sidebarMaterialView.blendingMode = .behindWindow
        sidebarMaterialView.state = .followsWindowActiveState

        for view in [sidebarInactiveFillView, toolbarFillView, dividerView, toolbarBottomDividerView] {
            view.wantsLayer = true
        }

        addSubview(sidebarMaterialView)
        addSubview(sidebarInactiveFillView)
        addSubview(toolbarFillView)
        addSubview(toolbarBottomDividerView)
        addSubview(dividerView)
    }

    @objc
    private func windowDidChangeKeyStatus() {
        updateAppearance()
    }

    private func updateAppearance() {
        let isWindowActive = window?.isKeyWindow ?? true

        sidebarMaterialView.state = .followsWindowActiveState
        sidebarMaterialView.isHidden = !isWindowActive
        sidebarInactiveFillView.isHidden = isWindowActive
        let chrome = WizardChrome.resolvedColor(.windowBackgroundColor, for: colorScheme).cgColor
        let divider = WizardChrome.resolvedColor(WizardDividerStyle.color, for: colorScheme).cgColor
        sidebarInactiveFillView.layer?.backgroundColor = chrome
        toolbarFillView.layer?.backgroundColor = chrome
        dividerView.layer?.backgroundColor = divider
        toolbarBottomDividerView.layer?.backgroundColor = divider
    }

    private var contentStartX: CGFloat {
        guard let splitView,
              let firstSubview = splitView.arrangedSubviews.first
        else {
            return sidebarWidth
        }

        let dividerTrailingEdgeInSplitView = firstSubview.frame.maxX + splitView.dividerThickness
        let dividerTrailingEdgeInWindow = splitView.convert(
            NSPoint(x: dividerTrailingEdgeInSplitView, y: 0),
            to: nil
        )
        return convert(dividerTrailingEdgeInWindow, from: nil).x
    }

}

extension NSUserInterfaceItemIdentifier {
    static let windowTitlebarChrome = NSUserInterfaceItemIdentifier("WindowTitlebarChrome")
}
