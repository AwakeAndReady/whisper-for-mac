import AppKit

enum WizardDividerStyle {
    static let color = NSColor.separatorColor

    @MainActor
    static func pixelWidth(for window: NSWindow?) -> CGFloat {
        1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
}
