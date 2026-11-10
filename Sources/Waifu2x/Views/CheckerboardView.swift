import SwiftUI

/// A quiet checkerboard shown behind transparent images. Squares stay in screen
/// space so the pattern remains subtle at every zoom level.
struct CheckerboardView: View {
    @Environment(\.colorScheme) private var colorScheme

    var square: CGFloat = 10

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(white: 0.17)
            : Color(white: 0.77)
    }

    private var alternateColor: Color {
        colorScheme == .dark
            ? Color(white: 0.23)
            : Color(white: 0.86)
    }

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(baseColor)
            )

            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : square
                while x < size.width {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: square, height: square)),
                        with: .color(alternateColor)
                    )
                    x += square * 2
                }
                row += 1
                y += square
            }
        }
        .accessibilityHidden(true)
    }
}
