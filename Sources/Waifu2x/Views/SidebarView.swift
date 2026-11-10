import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                if model.items.isEmpty {
                    SidebarEmptyView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                } else {
                    ForEach(model.items) { item in
                        SidebarRow(item: item)
                            .tag(item.id)
                            .contextMenu {
                                contextMenu(for: item)
                            }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Изображения")
                    Spacer(minLength: 0)
                    if !model.items.isEmpty {
                        Text("\(model.items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            model.deleteSelection()
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ImageItem) -> some View {
        Button("Улучшить") {
            model.improve(item)
        }
        .disabled(model.isProcessing)

        Button("Экспортировать…") {
            model.export(item)
        }

        Button("Показать в Finder") {
            model.revealInFinder(item)
        }

        Divider()

        Button("Удалить", role: .destructive) {
            model.delete(item)
        }
        .disabled(model.isProcessing)
    }
}

// MARK: - Row

private struct SidebarRow: View {
    @ObservedObject var item: ImageItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: Theme.thumbnailSize, height: Theme.thumbnailSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    statusIndicator

                    Text(item.status.title)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(item.compactSizeText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(item.errorMessage ?? item.displayName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(item.displayName), \(item.status.title), \(item.sourceSizeText)"))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if item.status == .processing {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.75)
                .frame(width: 9, height: 9)
        } else {
            Image(systemName: item.status.symbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.statusColor(for: item.status))
        }
    }
}

// MARK: - Empty sidebar

private struct SidebarEmptyView: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 26, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text("Нет изображений")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .accessibilityElement(children: .combine)
    }
}
