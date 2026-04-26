import AppKit

final class WindowTitlebarChromeView: NSView {
    private let sidebarMaterialView = NSVisualEffectView()
    private let sidebarInactiveFillView = NSView()
    private let toolbarFillView = NSView()
    private let dividerView = NSView()

    private var sidebarWidth: CGFloat
    private weak var splitView: NSSplitView?

    init(sidebarWidth: CGFloat) {
        self.sidebarWidth = sidebarWidth
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

    override func layout() {
        super.layout()

        let rightX = min(bounds.width, max(0, contentStartX))
        let dividerWidth = Self.dividerWidth(for: window)
        let dividerX = min(bounds.width - dividerWidth, max(0, rightX - (dividerWidth / 2)))

        sidebarMaterialView.frame = NSRect(x: 0, y: 0, width: rightX, height: bounds.height)
        sidebarInactiveFillView.frame = sidebarMaterialView.frame
        dividerView.frame = NSRect(x: dividerX, y: 0, width: dividerWidth, height: bounds.height)
        toolbarFillView.frame = NSRect(x: rightX, y: 0, width: max(0, bounds.width - rightX), height: bounds.height)
    }

    func update(sidebarWidth: CGFloat, splitView: NSSplitView?) {
        self.sidebarWidth = sidebarWidth
        self.splitView = splitView
        updateAppearance()
        needsLayout = true
    }

    private func configureSubviews() {
        autoresizingMask = [.width, .height]

        sidebarMaterialView.material = .sidebar
        sidebarMaterialView.blendingMode = .behindWindow
        sidebarMaterialView.state = .followsWindowActiveState

        for view in [sidebarInactiveFillView, toolbarFillView, dividerView] {
            view.wantsLayer = true
        }

        addSubview(sidebarMaterialView)
        addSubview(sidebarInactiveFillView)
        addSubview(toolbarFillView)
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
        sidebarInactiveFillView.layer?.backgroundColor = Self.inactiveChrome.cgColor
        toolbarFillView.layer?.backgroundColor = (isWindowActive ? Self.activeToolbarChrome : Self.inactiveChrome).cgColor
        dividerView.layer?.backgroundColor = Self.titlebarDividerColor.cgColor
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

    private static let inactiveChrome = NSColor(
        srgbRed: 228.0 / 255.0,
        green: 228.0 / 255.0,
        blue: 235.0 / 255.0,
        alpha: 1
    )
    private static let activeToolbarChrome = NSColor(
        srgbRed: 246.0 / 255.0,
        green: 244.0 / 255.0,
        blue: 250.0 / 255.0,
        alpha: 1
    )
    private static let titlebarDividerColor = NSColor.black.withAlphaComponent(0.14)

    private static func dividerWidth(for window: NSWindow?) -> CGFloat {
        1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let windowTitlebarChrome = NSUserInterfaceItemIdentifier("WindowTitlebarChrome")
}
