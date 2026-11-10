import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            symbolComposition
                .padding(.bottom, 28)

            Text("Перетащите изображения")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("PNG, JPEG, HEIC, TIFF или WebP. Всё обрабатывается локально на этом Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 390)
                .padding(.top, 8)

            Button {
                model.presentOpenPanel()
            } label: {
                Label("Открыть изображения…", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 24)
            .help("Открыть изображения (⌘O)")
            .accessibilityLabel("Открыть изображения")
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : reduceMotion ? 0 : 8)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            }
        }
    }

    private var symbolComposition: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.15),
                            Color.accentColor.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.10), lineWidth: 0.5)
                }
                .frame(width: 152, height: 152)
                .shadow(color: Color.accentColor.opacity(0.10), radius: 26, y: 10)

            Circle()
                .strokeBorder(
                    Color.primary.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 5])
                )
                .frame(width: 176, height: 176)

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Image(systemName: "sparkles")
                .font(.system(size: 23, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .offset(x: 52, y: -42)
                .accessibilityHidden(true)
        }
        .frame(width: 190, height: 170)
        .accessibilityHidden(true)
    }
}
