import AppKit
import SwiftUI

enum HoverSurfaceStyle {
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 10
    static let borderOpacity: Double = 0.18
    static let shadowOpacity: Double = 0.16
    static let shadowRadius: CGFloat = 10
    static let shadowYOffset: CGFloat = 4

    static func renderedWidth(forContentWidth contentWidth: CGFloat) -> CGFloat {
        contentWidth + horizontalPadding * 2
    }

    static func tintOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.72 : 0.84
    }

    static func secondaryTextOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.82 : 0.76
    }

    static func tertiaryTextOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.68 : 0.60
    }
}

private struct ReadableHoverSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HoverSurfaceStyle.cornerRadius, style: .continuous)

        content
            .padding(HoverSurfaceStyle.horizontalPadding)
            .background {
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(HoverSurfaceStyle.tintOpacity(for: colorScheme))
                    )
                }
            }
            .overlay {
                shape.stroke(
                    Color(nsColor: .separatorColor).opacity(HoverSurfaceStyle.borderOpacity),
                    lineWidth: 1
                )
            }
            .shadow(
                color: .black.opacity(HoverSurfaceStyle.shadowOpacity),
                radius: HoverSurfaceStyle.shadowRadius,
                y: HoverSurfaceStyle.shadowYOffset
            )
    }
}

extension View {
    func readableHoverSurface() -> some View {
        modifier(ReadableHoverSurfaceModifier())
    }
}
