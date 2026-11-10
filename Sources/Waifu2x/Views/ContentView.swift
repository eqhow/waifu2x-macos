import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: Theme.sidebarMinWidth,
                    ideal: Theme.sidebarIdealWidth,
                    max: Theme.sidebarMaxWidth
                )
        } detail: {
            VStack(spacing: 0) {
                CanvasView()
                StatusBarView()
            }
            .frame(minWidth: Theme.detailMinWidth, minHeight: 420)
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $model.inspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(
                    min: Theme.inspectorMinWidth,
                    ideal: Theme.inspectorIdealWidth,
                    max: Theme.inspectorMaxWidth
                )
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(Theme.canvasBackground)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.presentOpenPanel()
                } label: {
                    Label("Открыть", systemImage: "folder")
                }
                .help("Открыть изображения (⌘O)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $model.compareEnabled) {
                    Label("Сравнить до и после", systemImage: "rectangle.split.2x1")
                }
                .toggleStyle(.button)
                .disabled(!model.canCompare)
                .help("Сравнить до и после (⌘\\)")

                Button {
                    model.exportSelected()
                } label: {
                    Label("Экспортировать", systemImage: "square.and.arrow.up")
                }
                .disabled(model.selectedItem == nil)
                .help("Экспортировать (⌘S)")

                Toggle(isOn: $model.inspectorPresented) {
                    Label("Инспектор", systemImage: "sidebar.right")
                }
                .toggleStyle(.button)
                .help("Инспектор (⌥⌘I)")

                Button {
                    model.improveSelected()
                } label: {
                    Label("Улучшить", systemImage: "wand.and.stars")
                }
                .labelStyle(.titleAndIcon)
                .disabled(model.selectedItem == nil || model.isProcessing)
                .help("Улучшить (⌘↩)")
            }
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: $model.isDropTargeted
        ) { providers in
            model.handleDrop(providers)
        }
        .overlay {
            dropHighlight
        }
        .alert(
            model.alert?.title ?? L10n.t("Ошибка"),
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("Ок", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .waifu2xOpenImages)) { _ in
            model.importPendingOpenImages()
        }
        .onChange(of: model.selection) { _, _ in
            model.selectionChanged()
        }
        .task {
            model.prepareEngine()
            #if DEBUG
            DebugBridge.start(model: model)
            #endif
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.isDropTargeted
        )
    }

    // MARK: Drag highlight

    @ViewBuilder
    private var dropHighlight: some View {
        if model.isDropTargeted {
            ZStack {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.045))
                    .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
                    .padding(12)

                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 30, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)

                    Text("Отпустите, чтобы открыть")
                        .font(.headline)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityLabel("Отпустите файлы, чтобы открыть изображения")
        }
    }
}
