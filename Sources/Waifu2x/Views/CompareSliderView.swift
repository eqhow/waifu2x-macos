import AppKit
import SwiftUI

/// Before/after split view. The original is clipped to the left of the
/// draggable divider; the enhanced result fills the right side.
struct CompareSliderView: View {
    let original: CGImage
    let result: CGImage
    let size: CGSize
    @Binding var fraction: CGFloat

    private var clampedFraction: CGFloat {
        min(max(fraction, 0.02), 0.98)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            displayedImage(result)
            displayedImage(original)
                .mask(alignment: .topLeading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(width: proxy.size.width * clampedFraction)
                    }
                }

            if size.width > 200, size.height > 110 {
                labels
            }

            divider
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "compare")
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Сравнение до и после")
        .accessibilityValue(Text(verbatim: L10n.f("%ld процентов", Int((clampedFraction * 100).rounded()))))
    }

    private func displayedImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
    }

    private var labels: some View {
        HStack(spacing: 0) {
            Pill(material: .thickMaterial) {
                Text("До")
            }
            Spacer(minLength: 0)
            Pill(material: .thickMaterial) {
                Text("После")
            }
        }
        .padding(10)
        .frame(width: size.width, alignment: .top)
        .allowsHitTesting(false)
    }

    private var divider: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 1.5)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0)

            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.68))
                )
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .frame(width: 34, height: size.height)
        .contentShape(Rectangle())
        .position(x: size.width * clampedFraction, y: size.height / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("compare"))
                .onChanged { value in
                    let raw = value.location.x / max(size.width, 1)
                    fraction = min(max(raw, 0.02), 0.98)
                }
        )
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help("Потяните, чтобы сравнить до и после")
        .accessibilityLabel("Граница сравнения")
        .accessibilityValue(Text(verbatim: L10n.f("%ld процентов", Int((clampedFraction * 100).rounded()))))
    }
}
