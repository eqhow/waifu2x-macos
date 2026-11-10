import SwiftUI

// MARK: - Small native building blocks

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

struct Pill<Content: View>: View {
    private let content: Content
    private let material: Material

    init(material: Material = .regularMaterial, @ViewBuilder content: () -> Content) {
        self.material = material
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(material, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

struct EngineBadge: View {
    let status: EngineStatus

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: Theme.engineColor(for: status.kind))
            Text(status.kind.shortLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help("\(status.title) · \(status.detail)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: L10n.f("Движок: %@. %@", status.title, status.detail)))
    }
}

struct ProcessingToast: View {
    let progress: UpscaleProgress?
    let percentage: String
    let passText: String
    let isCancelling: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.t(isCancelling ? "Отмена…" : "Обработка…"))
                    .font(.callout.weight(.semibold))

                Text(percentage)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("Отмена", action: onCancel)
                    .controlSize(.small)
                    .disabled(isCancelling)
                    .help("Отменить обработку (⌘.)")
            }

            ProgressView(value: min(max(progress?.fraction ?? 0, 0), 1))
                .progressViewStyle(.linear)
                .tint(.accentColor)

            if !passText.isEmpty {
                Text(passText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 328)
        .background(
            .thickMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.20), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: L10n.f("Обработка изображения. %@. %@", percentage, passText)))
        .accessibilityAction(named: Text(L10n.t("Отменить обработку")), onCancel)
    }
}
