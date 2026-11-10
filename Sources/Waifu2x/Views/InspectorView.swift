import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    private var controlsDisabled: Bool {
        model.selectedItem == nil || model.isProcessing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                optionsSection
                actionSection
                fileSection
                resultSection
                engineSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityLabel("Инспектор")
    }

    // MARK: Апскейл

    private var optionsSection: some View {
        InspectorSection("Апскейл") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Стиль")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Стиль", selection: $model.options.style) {
                    ForEach(UpscaleOptions.Style.allCases) { style in
                        Text(style.localizedTitle).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(controlsDisabled)

            HStack(spacing: 8) {
                Text("Шумоподавление")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)

                Picker("Шумоподавление", selection: $model.options.denoise) {
                    ForEach(UpscaleOptions.Denoise.allCases) { level in
                        Text(level.localizedTitle).tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: 104)
                .disabled(controlsDisabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Масштаб")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Масштаб", selection: $model.options.scale) {
                    ForEach(UpscaleOptions.Scale.allCases) { scale in
                        Text("\(scale.rawValue)×").tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(controlsDisabled)
        }
    }

    // MARK: Actions

    private var actionSection: some View {
        InspectorSection("Действия") {
            if model.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: min(max(model.progress?.fraction ?? 0, 0), 1))
                        .progressViewStyle(.linear)

                    HStack {
                        Text(L10n.t(model.isCancelling ? "Отмена…" : "Обработка…"))
                            .font(.callout)
                        Spacer()
                        Text(model.progressPercentageText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.cancelProcessing()
                } label: {
                    Label("Отмена", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isCancelling)
                .help("Отменить обработку (⌘.)")
            } else {
                Button {
                    model.improveSelected()
                } label: {
                    Label("Улучшить", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(model.selectedItem == nil)
                .help("Улучшить (⌘↩)")

                Button {
                    model.improveAll()
                } label: {
                    Text("Улучшить всё")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.items.isEmpty)
                .help("Улучшить всё (⇧⌘↩)")
            }
        }
    }

    // MARK: File

    private var fileSection: some View {
        InspectorSection("Файл") {
            HStack(spacing: 8) {
                Text("Имя")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(model.selectedItem?.displayName ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.callout)

            HStack(alignment: .top, spacing: 10) {
                InspectorMetric("Размер", value: model.selectedItem?.compactSizeText ?? "—", monospaced: true)
                    .frame(width: 98, alignment: .leading)
                InspectorMetric("Формат", value: model.selectedItem?.formatLabel ?? "—")
                InspectorMetric("Вес", value: model.selectedItem?.fileSizeText ?? "—", monospaced: true)
            }
            .padding(.top, 2)
        }
    }

    // MARK: Result

    private var resultSection: some View {
        InspectorSection("Результат") {
            HStack(alignment: .top, spacing: 10) {
                InspectorMetric("Размер", value: resultSizeText, monospaced: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Статус")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let item = model.selectedItem {
                        HStack(spacing: 5) {
                            StatusDot(color: Theme.statusColor(for: item.status))
                            Text(item.status.title)
                        }
                        .font(.callout)
                    } else {
                        Text("—")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var resultSizeText: String {
        guard let size = model.selectedItem?.resultSize else { return "—" }
        return Formatting.compactPixelSize(size)
    }

    // MARK: Engine

    private var engineSection: some View {
        InspectorSection("Движок") {
            HStack(alignment: .top, spacing: 8) {
                StatusDot(color: Theme.engineColor(for: model.engineStatus.kind))
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.engineStatus.title)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.engineStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if model.isPreparingEngine {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if model.engineStatus.kind == .fallback {
                Text("Core ML недоступен — используется резервный Lanczos-движок.")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Проверить модели") {
                model.prepareEngine(force: true)
            }
            .controlSize(.small)
            .disabled(model.isPreparingEngine)
            .help("Повторно проверить доступность моделей")
        }
    }
}

// MARK: - Building blocks

private struct InspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.62)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.055)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(cardStroke, lineWidth: 0.5)
                    }
            }
        }
    }
}

private struct InspectorMetric: View {
    let label: LocalizedStringKey
    let value: String
    var monospaced = false

    init(_ label: LocalizedStringKey, value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(monospaced ? .callout.monospacedDigit() : .callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryActionButton(configuration: configuration)
    }
}

private struct PrimaryActionButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(isEnabled ? Color.white : Color(nsColor: .tertiaryLabelColor))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.primary.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isEnabled ? Color.white.opacity(0.12) : Color.primary.opacity(0.035),
                                lineWidth: 0.5
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .brightness(isEnabled && isHovering ? 0.035 : 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .onHover { isHovering = $0 }
    }
}
