import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared preferences

enum SettingsKeys {
    static let style = "defaultStyle"
    static let denoise = "defaultDenoise"
    static let scale = "defaultScale"
    static let autoCompare = "autoCompareAfterProcessing"
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

enum ZoomState: Equatable {
    case fit
    case actual
    case custom(Double)
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    // MARK: Queue

    @Published var items: [ImageItem] = []
    @Published var selection: UUID?

    // MARK: Options & engine

    @Published var options: UpscaleOptions {
        didSet { persistOptions() }
    }
    @Published var engineStatus: EngineStatus = .preparing
    @Published var isPreparingEngine = false

    // MARK: Job state

    @Published var isProcessing = false
    @Published var isCancelling = false
    @Published var progress: UpscaleProgress?
    @Published var activeItemID: UUID?
    @Published var processedCount = 0
    @Published var batchTotal = 0
    @Published var lastRunWasCancelled = false
    @Published var lastRunHadError = false

    // MARK: Presentation

    @Published var compareEnabled = true
    @Published var compareFraction: CGFloat = 0.5
    @Published var zoom: ZoomState = .fit
    @Published var fitScale: Double = 1
    @Published var inspectorPresented = true
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var isDropTargeted = false
    @Published var alert: AppAlert?

    // MARK: Private

    private var cancellation: CancellationToken?
    private var processingTask: Task<Void, Never>?
    private var hasPreparedEngine = false
    private var cancelledItemsDuringBatch: Set<UUID> = []

    private static let zoomStops: [Double] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

    // MARK: Init

    init() {
        let defaults = UserDefaults.standard
        let style = UpscaleOptions.Style(
            rawValue: defaults.string(forKey: SettingsKeys.style) ?? ""
        ) ?? .anime
        let denoiseRaw = (defaults.object(forKey: SettingsKeys.denoise) as? Int)
            ?? UpscaleOptions.Denoise.low.rawValue
        let denoise = UpscaleOptions.Denoise(rawValue: denoiseRaw) ?? .low
        let scaleRaw = (defaults.object(forKey: SettingsKeys.scale) as? Int)
            ?? UpscaleOptions.Scale.x2.rawValue
        let scale = UpscaleOptions.Scale(rawValue: scaleRaw) ?? .x2

        self.options = UpscaleOptions(style: style, denoise: denoise, scale: scale)

        let hasAutoCompareSetting = defaults.object(forKey: SettingsKeys.autoCompare) != nil
        self.compareEnabled = hasAutoCompareSetting ? defaults.bool(forKey: SettingsKeys.autoCompare) : true

        let pending = PendingOpenImages.shared.takeAll()
        if !pending.isEmpty {
            Task { [weak self] in
                self?.importImages(urls: pending)
            }
        }
    }

    // MARK: Derived state

    var selectedItem: ImageItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    var currentZoomScale: Double {
        switch zoom {
        case .fit:
            return min(max(fitScale, 0.1), 4)
        case .actual:
            return 1
        case .custom(let value):
            return min(max(value, 0.1), 4)
        }
    }

    var zoomPercentText: String {
        "\(Int((currentZoomScale * 100).rounded()))%"
    }

    var canCompare: Bool {
        selectedItem?.result != nil
    }

    var compareActive: Bool {
        compareEnabled && selectedItem?.result != nil
    }

    var isValidatingSelection: Bool {
        selectedItem != nil
    }

    var jobStatusText: String {
        if isProcessing {
            return isCancelling ? L10n.t("Отмена…") : L10n.t("Обработка…")
        }
        if isPreparingEngine {
            return L10n.t("Подготовка моделей…")
        }
        if lastRunHadError {
            return L10n.t("Ошибка")
        }
        if lastRunWasCancelled {
            return L10n.t("Отменено")
        }
        if !items.isEmpty {
            return L10n.t("Готово")
        }
        return ""
    }

    var progressPercentageText: String {
        let fraction = min(max(progress?.fraction ?? 0, 0), 1)
        return "\(Int((fraction * 100).rounded()))%"
    }

    var progressDetailText: String {
        progress?.detail ?? ""
    }

    /// A shorter variant for the narrow status bar. For a single pass it drops
    /// the redundant "Проход 1 из 1" prefix; for 4× it shows "Проход 1/2".
    var compactProgressDetailText: String {
        guard let progress else { return "" }
        if progress.passCount == 1,
           let separator = progress.detail.range(of: "· ") {
            return String(progress.detail[separator.upperBound...])
        }
        let separator = L10n.isRussian ? " из " : " of "
        return progress.detail.replacingOccurrences(of: separator, with: "/")
    }

    var batchPositionText: String {
        guard isProcessing, batchTotal > 1 else { return "" }
        let current = min(processedCount + 1, batchTotal)
        return L10n.f("%ld из %ld", current, batchTotal)
    }

    // MARK: Import

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = L10n.t("Выберите изображения для улучшения")
        panel.prompt = L10n.t("Открыть")
        if panel.runModal() == .OK {
            importImages(urls: panel.urls)
        }
    }

    func importPendingOpenImages() {
        let urls = PendingOpenImages.shared.takeAll()
        guard !urls.isEmpty else { return }
        importImages(urls: urls)
    }

    func importImages(urls: [URL]) {
        guard !urls.isEmpty else { return }

        Task {
            var loaded: [LoadedImage] = []
            var failures: [String] = []

            for url in urls {
                do {
                    let image = try await Task.detached(priority: .userInitiated) {
                        try ImageLoader.load(url: url)
                    }.value
                    loaded.append(image)
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }

            let previousSelection = selection
            var firstNewID: UUID?

            for image in loaded {
                let item = ImageItem(loaded: image)
                items.append(item)
                if firstNewID == nil {
                    firstNewID = item.id
                }
            }

            if previousSelection == nil, let firstNewID {
                selection = firstNewID
            }

            if !failures.isEmpty {
                let names = failures.map { "• \($0)" }.joined(separator: "\n")
                alert = AppAlert(
                    title: L10n.t("Не удалось открыть изображение"),
                    message: L10n.f("Пропущены файлы:\n%@", names)
                )
            }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await Self.fileURL(from: provider), ImageLoader.isImageFile(url) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                importImages(urls: urls)
            }
        }
        return true
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                } else if let nsURL = item as? NSURL {
                    url = nsURL as URL
                } else {
                    url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: Queue editing

    func deleteSelection() {
        guard let selection, !isProcessing else { return }
        removeItem(id: selection)
    }

    func delete(_ item: ImageItem) {
        guard !isProcessing else { return }
        removeItem(id: item.id)
    }

    private func removeItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if selection == id {
            selection = items.isEmpty ? nil : items[min(index, items.count - 1)].id
            zoom = .fit
        }
    }

    func revealInFinder(_ item: ImageItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
    }

    func selectionChanged() {
        zoom = .fit
        fitScale = 1
        compareFraction = 0.5
    }

    // MARK: Processing

    func improveSelected() {
        guard let item = selectedItem, !isProcessing else { return }
        startBatch(itemIDs: [item.id])
    }

    func improve(_ item: ImageItem) {
        guard !isProcessing else { return }
        startBatch(itemIDs: [item.id])
    }

    func improveAll() {
        guard !items.isEmpty, !isProcessing else { return }
        let pending = items.filter { $0.status != .done }
        let ids = pending.isEmpty ? items.map(\.id) : pending.map(\.id)
        startBatch(itemIDs: ids)
    }

    func retry(_ item: ImageItem) {
        guard !isProcessing else { return }
        item.status = .queued
        item.errorMessage = nil
        startBatch(itemIDs: [item.id])
    }

    func cancelProcessing() {
        guard isProcessing, !isCancelling else { return }
        isCancelling = true
        cancellation?.cancel()
    }

    private func startBatch(itemIDs: [UUID]) {
        guard !isProcessing else { return }
        let knownIDs = Set(items.map(\.id))
        let validIDs = itemIDs.filter { knownIDs.contains($0) }
        guard !validIDs.isEmpty else { return }

        let snapshot = options
        let token = CancellationToken()

        cancellation = token
        isProcessing = true
        isCancelling = false
        lastRunWasCancelled = false
        lastRunHadError = false
        activeItemID = nil
        processedCount = 0
        batchTotal = validIDs.count
        progress = nil

        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.runBatch(ids: validIDs, options: snapshot, token: token)
        }
    }

    private func runBatch(ids: [UUID], options: UpscaleOptions, token: CancellationToken) async {
        for id in ids {
            if token.isCancelled {
                break
            }
            guard let item = items.first(where: { $0.id == id }) else {
                continue
            }

            activeItemID = id
            item.status = .processing
            item.errorMessage = nil
            item.progressFraction = 0
            progress = UpscaleProgress(
                fraction: 0,
                pass: 1,
                passCount: options.passCount,
                detail: ""
            )

            do {
                let result = try await ProcessingService.shared.upscale(
                    item.original,
                    options: options,
                    progress: { update in
                        Task { @MainActor [weak self] in
                            guard let self, self.activeItemID == id else { return }
                            self.progress = update
                            self.items.first { $0.id == id }?.progressFraction = update.fraction
                        }
                    },
                    cancellation: token
                )

                if token.isCancelled {
                    break
                }

                item.result = result
                item.optionsUsed = options
                item.processedAt = Date()
                item.status = .done
                item.progressFraction = 1
                processedCount += 1

                if selection == id {
                    zoom = .fit
                    compareFraction = 0.5
                    if Self.autoComparePreference() {
                        compareEnabled = true
                    }
                }
            } catch {
                if isCancellation(error, token: token) {
                    item.status = item.result == nil ? .queued : .done
                    item.progressFraction = 0
                    lastRunWasCancelled = true
                    break
                }

                item.status = .failed
                item.errorMessage = error.localizedDescription
                lastRunHadError = true
                alert = AppAlert(
                    title: L10n.t("Не удалось обработать изображение"),
                    message: error.localizedDescription
                )
                break
            }
        }

        finishBatch(cancelled: token.isCancelled)
    }

    private func finishBatch(cancelled: Bool) {
        isProcessing = false
        isCancelling = false
        activeItemID = nil
        progress = nil
        cancellation = nil
        processingTask = nil
        if cancelled {
            lastRunWasCancelled = true
        }
    }

    private func isCancellation(_ error: Error, token: CancellationToken) -> Bool {
        if token.isCancelled { return true }
        if error is CancellationError { return true }
        if let upscaleError = error as? UpscaleError, case .cancelled = upscaleError {
            return true
        }
        return false
    }

    private static func autoComparePreference() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKeys.autoCompare) == nil {
            return true
        }
        return defaults.bool(forKey: SettingsKeys.autoCompare)
    }

    // MARK: Engine

    func prepareEngine(force: Bool = false) {
        guard !isPreparingEngine else { return }
        if !force, hasPreparedEngine { return }

        isPreparingEngine = true
        engineStatus = .preparing

        Task {
            let status = await ProcessingService.shared.prepare()
            engineStatus = status
            isPreparingEngine = false
            hasPreparedEngine = true
        }
    }

    // MARK: Options from settings

    func syncOptionsFromDefaults() {
        let defaults = UserDefaults.standard
        let style = UpscaleOptions.Style(
            rawValue: defaults.string(forKey: SettingsKeys.style) ?? ""
        ) ?? .anime
        let denoiseRaw = (defaults.object(forKey: SettingsKeys.denoise) as? Int)
            ?? UpscaleOptions.Denoise.low.rawValue
        let denoise = UpscaleOptions.Denoise(rawValue: denoiseRaw) ?? .low
        let scaleRaw = (defaults.object(forKey: SettingsKeys.scale) as? Int)
            ?? UpscaleOptions.Scale.x2.rawValue
        let scale = UpscaleOptions.Scale(rawValue: scaleRaw) ?? .x2

        let updated = UpscaleOptions(style: style, denoise: denoise, scale: scale)
        if updated != options {
            options = updated
        }
    }

    private func persistOptions() {
        let defaults = UserDefaults.standard
        defaults.set(options.style.rawValue, forKey: SettingsKeys.style)
        defaults.set(options.denoise.rawValue, forKey: SettingsKeys.denoise)
        defaults.set(options.scale.rawValue, forKey: SettingsKeys.scale)
    }

    // MARK: Zoom

    func reportFitScale(_ scale: Double) {
        let clamped = min(max(scale, 0.1), 4)
        if abs(fitScale - clamped) > 0.0005 {
            fitScale = clamped
        }
    }

    func zoomIn() {
        guard selectedItem != nil else { return }
        let current = currentZoomScale
        if let next = Self.zoomStops.first(where: { $0 > current + 0.001 }) {
            zoom = .custom(next)
        } else {
            zoom = .custom(4)
        }
    }

    func zoomOut() {
        guard selectedItem != nil else { return }
        let current = currentZoomScale
        if let previous = Self.zoomStops.last(where: { $0 < current - 0.001 }) {
            zoom = .custom(previous)
        } else {
            zoom = .custom(0.1)
        }
    }

    func zoomToFit() {
        guard selectedItem != nil else { return }
        zoom = .fit
    }

    func zoomToActualSize() {
        guard selectedItem != nil else { return }
        zoom = .actual
    }

    func toggleFitAndActual() {
        guard selectedItem != nil else { return }
        zoom = zoom == .actual ? .fit : .actual
    }

    // MARK: Presentation

    func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    func toggleInspector() {
        inspectorPresented.toggle()
    }

    func toggleCompare() {
        guard canCompare else { return }
        compareEnabled.toggle()
    }

    // MARK: Export

    func exportSelected() {
        guard let item = selectedItem else { return }
        presentSavePanel(for: item)
    }

    func export(_ item: ImageItem) {
        presentSavePanel(for: item)
    }

    func exportAll() {
        guard !items.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = L10n.t("Выберите папку для экспорта")
        panel.prompt = L10n.t("Экспортировать")

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        var failures: [String] = []
        for item in items {
            let suffix = item.result != nil ? item.suggestedExportSuffix : ""
            let base = item.sourceURL.deletingPathExtension().lastPathComponent + suffix
            let url = uniqueURL(in: directory, base: base, extension: "png")
            do {
                try write(image: item.result ?? item.original, to: url, type: .png)
            } catch {
                failures.append("\(item.displayName): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            alert = AppAlert(
                title: L10n.t("Не удалось экспортировать"),
                message: failures.joined(separator: "\n")
            )
        }
    }

    private func presentSavePanel(for item: ImageItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = L10n.t("Экспортировать изображение")
        panel.prompt = L10n.t("Экспортировать")

        let controller = ExportFormatController()
        let baseName = item.sourceURL.deletingPathExtension().lastPathComponent
            + (item.result != nil ? item.suggestedExportSuffix : "")
        controller.configure(panel: panel, baseName: baseName)
        panel.accessoryView = makeExportAccessory(controller: controller)

        guard panel.runModal() == .OK, var url = panel.url else { return }

        let type = controller.type
        let expectedExtension = type.preferredFilenameExtension ?? "png"
        if url.pathExtension.lowercased() != expectedExtension {
            url = url.deletingPathExtension().appendingPathExtension(expectedExtension)
        }

        do {
            try write(image: item.result ?? item.original, to: url, type: type)
        } catch {
            alert = AppAlert(
                title: L10n.t("Не удалось экспортировать"),
                message: error.localizedDescription
            )
        }
    }

    private func makeExportAccessory(controller: ExportFormatController) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))

        let label = NSTextField(labelWithString: L10n.t("Формат:"))
        label.frame = NSRect(x: 0, y: 12, width: 58, height: 20)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor

        controller.popup.frame = NSRect(x: 62, y: 8, width: 120, height: 28)

        view.addSubview(label)
        view.addSubview(controller.popup)
        return view
    }

    private func uniqueURL(in directory: URL, base: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private func write(image: CGImage, to url: URL, type: UTType) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw UpscaleError.exportFailed(L10n.t("Не удалось создать файл."))
        }

        var properties: [CFString: Any] = [:]
        if type.conforms(to: .jpeg) {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw UpscaleError.exportFailed(L10n.t("Не удалось записать данные изображения."))
        }
    }
}

// MARK: - Export format accessory

private final class ExportFormatController: NSObject {
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private weak var panel: NSSavePanel?
    private(set) var type: UTType = .png
    private var baseName = ""

    override init() {
        super.init()
        popup.addItems(withTitles: ["PNG", "JPEG"])
        popup.target = self
        popup.action = #selector(formatChanged)
        popup.selectItem(at: 0)
    }

    func configure(panel: NSSavePanel, baseName: String) {
        self.panel = panel
        self.baseName = baseName
        panel.nameFieldStringValue = baseName + ".png"
    }

    @objc private func formatChanged() {
        type = popup.indexOfSelectedItem == 1 ? .jpeg : .png
        guard let panel else { return }
        let typedName = URL(fileURLWithPath: panel.nameFieldStringValue)
            .deletingPathExtension()
            .lastPathComponent
        let name = typedName.isEmpty ? baseName : typedName
        let ext = type.preferredFilenameExtension ?? "png"
        panel.nameFieldStringValue = "\(name).\(ext)"
    }
}
