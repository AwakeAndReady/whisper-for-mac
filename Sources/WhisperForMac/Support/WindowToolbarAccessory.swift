import AppKit

final class WindowTitlebarChromeView: NSView {
    private let sidebarMaterialView = NSVisualEffectView()
    private let sidebarTintView = NSView()
    private let sidebarInactiveFillView = NSView()
    private let toolbarFillView = NSView()
    private let dividerView = NSView()

    private var sidebarWidth: CGFloat
    private var isWindowActive: Bool

    init(sidebarWidth: CGFloat, isWindowActive: Bool) {
        self.sidebarWidth = sidebarWidth
        self.isWindowActive = isWindowActive
        super.init(frame: .zero)
        configureSubviews()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()

        let leftWidth = min(max(0, sidebarWidth), bounds.width)
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let dividerWidth = 1 / backingScale
        let dividerX = min(leftWidth, max(0, bounds.width - dividerWidth))
        let rightX = min(bounds.width, dividerX + dividerWidth)

        sidebarMaterialView.frame = NSRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
        sidebarTintView.frame = sidebarMaterialView.frame
        sidebarInactiveFillView.frame = sidebarMaterialView.frame
        dividerView.frame = NSRect(x: dividerX, y: 0, width: dividerWidth, height: bounds.height)
        toolbarFillView.frame = NSRect(x: rightX, y: 0, width: max(0, bounds.width - rightX), height: bounds.height)
    }

    func update(sidebarWidth: CGFloat, isWindowActive: Bool) {
        self.sidebarWidth = sidebarWidth
        self.isWindowActive = isWindowActive
        updateAppearance()
        needsLayout = true
    }

    private func configureSubviews() {
        autoresizingMask = [.width, .height]

        sidebarMaterialView.material = .sidebar
        sidebarMaterialView.blendingMode = .behindWindow
        sidebarMaterialView.state = .active

        for view in [sidebarTintView, sidebarInactiveFillView, toolbarFillView, dividerView] {
            view.wantsLayer = true
        }

        addSubview(sidebarMaterialView)
        addSubview(sidebarTintView)
        addSubview(sidebarInactiveFillView)
        addSubview(toolbarFillView)
        addSubview(dividerView)
    }

    private func updateAppearance() {
        sidebarMaterialView.isHidden = !isWindowActive
        sidebarTintView.isHidden = !isWindowActive
        sidebarInactiveFillView.isHidden = isWindowActive

        sidebarTintView.layer?.backgroundColor = Self.activeSidebarTint.withAlphaComponent(0.18).cgColor
        sidebarInactiveFillView.layer?.backgroundColor = Self.inactiveChrome.cgColor
        toolbarFillView.layer?.backgroundColor = (isWindowActive ? Self.activeToolbarChrome : Self.inactiveChrome).cgColor
        dividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
    }

    private static let inactiveChrome = NSColor(
        srgbRed: 233.0 / 255.0,
        green: 232.0 / 255.0,
        blue: 237.0 / 255.0,
        alpha: 1
    )
    private static let activeToolbarChrome = NSColor(
        srgbRed: 246.0 / 255.0,
        green: 244.0 / 255.0,
        blue: 250.0 / 255.0,
        alpha: 1
    )
    private static let activeSidebarTint = NSColor(
        srgbRed: 233.0 / 255.0,
        green: 232.0 / 255.0,
        blue: 237.0 / 255.0,
        alpha: 1
    )
}

extension NSUserInterfaceItemIdentifier {
    static let windowTitlebarChrome = NSUserInterfaceItemIdentifier("WindowTitlebarChrome")
}
