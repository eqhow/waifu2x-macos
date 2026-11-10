import AppKit
import SwiftUI

struct CanvasView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.canvasBackground
                .ignoresSafeArea()

            if let item = model.selectedItem {
                stage(for: item)
            } else {
                EmptyStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: model.selectedItem?.id
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: model.compareEnabled
        )
    }

    // MARK: Stage

    private func stage(for item: ImageItem) -> some View {
        GeometryReader { geometry in
            let available = CGSize(
                width: max(geometry.size.width - 112, 120),
                height: max(geometry.size.height - 132, 120)
            )
            let imageSize = item.displaySize
            let fit = fitScale(for: imageSize, in: available)
            let scale = resolvedScale(fit: fit)
            let displayedSize = CGSize(
                width: max(imageSize.width * scale, 1),
                height: max(imageSize.height * scale, 1)
            )

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    imageCard(for: item, displayedSize: displayedSize)
                        .padding(56)
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .defaultScrollAnchor(.center)
            .overlay(alignment: .bottom) {
                queueOverlay(for: item)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
            .overlay {
                errorOverlay(for: item)
            }
            .onAppear {
                model.reportFitScale(fit)
            }
            .onChange(of: fit) { _, newFit in
                model.reportFitScale(newFit)
            }
            .onChange(of: item.displaySize) { _, _ in
                model.reportFitScale(fit)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: model.isProcessing
            )
        }
    }

    // MARK: Image card

    private func imageCard(for item: ImageItem, displayedSize: CGSize) -> some View {
        ZStack {
            CheckerboardView()

            if model.compareEnabled, let result = item.result {
                CompareSliderView(
                    original: item.original,
                    result: result,
                    size: displayedSize,
                    fraction: $model.compareFraction
                )
            } else {
                Image(decorative: item.displayImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayedSize.width, height: displayedSize.height)
                    .accessibilityLabel(Text(verbatim: L10n.f("Изображение %@", item.displayName)))
            }
        }
        .frame(width: displayedSize.width, height: displayedSize.height)
        .clipShape(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: Theme.cardShadow, radius: 22, y: 9)
        .overlay(alignment: .bottomLeading) {
            dimensionPill(for: item)
                .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.toggleFitAndActual()
        }
        .help("Дважды щёлкните, чтобы вписать изображение или показать 100%")
    }

    private func dimensionPill(for item: ImageItem) -> some View {
        Pill(material: .thickMaterial) {
            HStack(spacing: 5) {
                Text(item.sourceSizeText)

                if let resultSize = item.resultSize {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(Formatting.pixelSize(resultSize))
                        .foregroundStyle(.tint)
                }
            }
            .monospacedDigit()
        }
        .allowsHitTesting(false)
        .accessibilityLabel(
            Text(verbatim: item.resultSize == nil
                ? item.sourceSizeText
                : L10n.f("До %@, после %@", item.sourceSizeText, item.resultSizeText))
        )
    }

    // MARK: Overlays

    @ViewBuilder
    private func queueOverlay(for item: ImageItem) -> some View {
        if model.isProcessing, model.activeItemID == item.id {
            ProcessingToast(
                progress: model.progress,
                percentage: model.progressPercentageText,
                passText: model.progressDetailText,
                isCancelling: model.isCancelling,
                onCancel: { model.cancelProcessing() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if model.isProcessing, item.status == .queued {
            Pill(material: .regularMaterial) {
                Label("В очереди", systemImage: "clock")
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func errorOverlay(for item: ImageItem) -> some View {
        if item.status == .failed, let message = item.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .systemOrange))

                Text("Не удалось обработать изображение")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 320)

                Button("Повторить") {
                    model.retry(item)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isProcessing)
                .padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            .padding(24)
            .transition(.opacity)
        }
    }

    // MARK: Zoom math

    private func fitScale(for imageSize: CGSize, in available: CGSize) -> Double {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let raw = min(
            available.width / imageSize.width,
            available.height / imageSize.height,
            1
        )
        return Double(min(max(raw, 0.1), 4))
    }

    private func resolvedScale(fit: Double) -> CGFloat {
        let scale: Double
        switch model.zoom {
        case .fit:
            scale = fit
        case .actual:
            scale = 1
        case .custom(let value):
            scale = value
        }
        return CGFloat(min(max(scale, 0.1), 4))
    }
}
