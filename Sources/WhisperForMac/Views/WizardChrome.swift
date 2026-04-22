import AppKit
import SwiftUI

enum WizardChrome {
    static let panelCornerRadius: CGFloat = 18
    static let sectionCornerRadius: CGFloat = 14
    static let appBackground = Color(.sRGB, red: 239.0 / 255.0, green: 235.0 / 255.0, blue: 236.0 / 255.0, opacity: 0.84)
    static let cardBackground = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.96)
    static let cardHeaderBackground = Color(.sRGB, red: 242.0 / 255.0, green: 238.0 / 255.0, blue: 239.0 / 255.0, opacity: 0.98)
    static let controlBackground = Color(.sRGB, red: 247.0 / 255.0, green: 243.0 / 255.0, blue: 244.0 / 255.0, opacity: 1)
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
