import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 10) {
                Text(Formatting.imagesCount(model.items.count))
                    .foregroundStyle(model.items.isEmpty ? .tertiary : .secondary)
                    .monospacedDigit()

                if !model.jobStatusText.isEmpty {
                    Divider()
                        .frame(height: 12)

                    Text(model.jobStatusText)
                        .foregroundStyle(statusColor)

                    if model.isPreparingEngine {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.72)
                            .frame(width: 12, height: 12)
                    }
                }

                if model.isProcessing {
                    ProgressView(value: min(max(model.progress?.fraction ?? 0, 0), 1))
                        .progressViewStyle(.linear)
                        .frame(width: 64)

                    if !model.batchPositionText.isEmpty {
                        Text(model.batchPositionText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if !model.compactProgressDetailText.isEmpty {
                        Text(model.compactProgressDetailText)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                }

                Spacer(minLength: 12)

                zoomControl

                Divider()
                    .frame(height: 14)

                EngineBadge(status: model.engineStatus)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.bar)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        if model.lastRunHadError {
            return Color(nsColor: .systemOrange)
        }
        if model.isProcessing || model.isPreparingEngine {
            return .secondary
        }
        if model.lastRunWasCancelled {
            return .secondary
        }
        return .secondary
    }

    private var zoomControl: some View {
        ControlGroup {
            Button {
                model.zoomOut()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 14, height: 14)
            }
            .disabled(model.selectedItem == nil)
            .help("Уменьшить (⌘−)")

            Button {
                model.zoomToFit()
            } label: {
                Text(model.zoomPercentText)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 40)
            }
            .disabled(model.selectedItem == nil)
            .help("Вписать (⌘9)")

            Button {
                model.zoomIn()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 14, height: 14)
            }
            .disabled(model.selectedItem == nil)
            .help("Увеличить (⌘+)")
        }
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(Text(verbatim: L10n.f("Масштаб %@", model.zoomPercentText)))
    }
}
