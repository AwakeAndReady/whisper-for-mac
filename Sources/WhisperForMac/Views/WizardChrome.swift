import AppKit
import SwiftUI

enum WizardChrome {
    static let panelCornerRadius: CGFloat = 18
    static let sectionCornerRadius: CGFloat = 14
    static let appBackground = Color(.sRGB, red: 239.0 / 255.0, green: 235.0 / 255.0, blue: 236.0 / 255.0, opacity: 0.84)
    static let cardBackground = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.96)
    static let cardHeaderBackground = Color(.sRGB, red: 242.0 / 255.0, green: 238.0 / 255.0, blue: 239.0 / 255.0, opacity: 0.98)
    static let controlBackground = Color(.sRGB, red: 239.0 / 255.0, green: 236.0 / 255.0, blue: 240.0 / 255.0, opacity: 1)
    static let inactiveChrome = Color(.sRGB, red: 228.0 / 255.0, green: 228.0 / 255.0, blue: 235.0 / 255.0, opacity: 1)
    static let activeToolbarChrome = Color(.sRGB, red: 246.0 / 255.0, green: 244.0 / 255.0, blue: 250.0 / 255.0, opacity: 1)
    static let activeSidebarTint = Color(.sRGB, red: 233.0 / 255.0, green: 232.0 / 255.0, blue: 237.0 / 255.0, opacity: 1)
}

private struct WhisperSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let fillOpacity: CGFloat
    let borderOpacity: CGFloat
    let fillColor: Color?
    let tint: Color?
    let tintOpacity: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill((fillColor ?? Color(nsColor: .controlBackgroundColor)).opacity(fillOpacity))
                    .overlay {
                        if let tint, tintOpacity > 0 {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(tintOpacity))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(borderOpacity), lineWidth: 1)
                    }
            }
    }
}

struct WhisperMenuField<MenuContent: View>: View {
    let title: String
    var isEnabled: Bool = true
    @ViewBuilder let content: () -> MenuContent

    var body: some View {
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
                    .fill(WizardChrome.controlBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.10), lineWidth: 1)
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
