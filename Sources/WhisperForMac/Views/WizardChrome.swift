import AppKit
import SwiftUI

@MainActor
enum WizardChrome {
    nonisolated static let panelCornerRadius: CGFloat = 18
    nonisolated static let sectionCornerRadius: CGFloat = 14

    @MainActor
    struct Palette {
        let appBackground: Color
        let cardBackground: Color
        let controlBackground: Color
        let inactiveChrome: Color
        let separator: Color

        init(colorScheme: ColorScheme) {
            appBackground = Color(nsColor: WizardChrome.resolvedColor(.windowBackgroundColor, for: colorScheme)).opacity(0.84)
            cardBackground = Color(nsColor: WizardChrome.resolvedColor(.controlBackgroundColor, for: colorScheme)).opacity(0.96)
            controlBackground = Color(nsColor: WizardChrome.resolvedColor(.controlBackgroundColor, for: colorScheme))
            inactiveChrome = Color(nsColor: WizardChrome.resolvedColor(.windowBackgroundColor, for: colorScheme))
            separator = Color(nsColor: WizardChrome.resolvedColor(.separatorColor, for: colorScheme))
        }
    }

    private static let lightPalette = Palette(colorScheme: .light)
    private static let darkPalette = Palette(colorScheme: .dark)

    static func palette(for colorScheme: ColorScheme) -> Palette {
        colorScheme == .dark ? darkPalette : lightPalette
    }

    static func resolvedColor(_ color: NSColor, for colorScheme: ColorScheme) -> NSColor {
        guard let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) else {
            return color
        }
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }
}

private struct WhisperSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let padding: CGFloat
    let cornerRadius: CGFloat
    let fillOpacity: CGFloat
    let borderOpacity: CGFloat
    let fillColor: Color?
    let tint: Color?
    let tintOpacity: CGFloat

    func body(content: Content) -> some View {
        let palette = WizardChrome.palette(for: colorScheme)
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill((fillColor ?? palette.cardBackground).opacity(fillOpacity))
                    .overlay {
                        if let tint, tintOpacity > 0 {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(tintOpacity))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(palette.separator.opacity(borderOpacity), lineWidth: 1)
                    }
            }
    }
}

struct WhisperMenuField<MenuContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var isEnabled: Bool = true
    @ViewBuilder let content: () -> MenuContent

    var body: some View {
        let palette = WizardChrome.palette(for: colorScheme)
        Menu {
            content()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.controlBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.separator.opacity(0.10), lineWidth: 1)
                    }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!isEnabled)
    }
}

extension View {
    func whisperSurface(
        padding: CGFloat = 18,
        cornerRadius: CGFloat = WizardChrome.panelCornerRadius,
        fillOpacity: CGFloat = 0.74,
        borderOpacity: CGFloat = 0.18,
        fillColor: Color? = nil,
        tint: Color? = nil,
        tintOpacity: CGFloat = 0
    ) -> some View {
        modifier(
            WhisperSurfaceModifier(
                padding: padding,
                cornerRadius: cornerRadius,
                fillOpacity: fillOpacity,
                borderOpacity: borderOpacity,
                fillColor: fillColor,
                tint: tint,
                tintOpacity: tintOpacity
            )
        )
    }
}
