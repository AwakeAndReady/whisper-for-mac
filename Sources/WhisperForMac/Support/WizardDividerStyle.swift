import AppKit

enum WizardDividerStyle {
    static let color = NSColor(
        srgbRed: 206.0 / 255.0,
        green: 205.0 / 255.0,
        blue: 197.0 / 255.0,
        alpha: 1
    )

    @MainActor
    static func pixelWidth(for window: NSWindow?) -> CGFloat {
        1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
}
