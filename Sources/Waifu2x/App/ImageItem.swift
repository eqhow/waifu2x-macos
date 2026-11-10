import AppKit
import CoreGraphics
import Foundation

enum ItemStatus: String, Equatable {
    case queued
    case processing
    case done
    case failed

    var title: String {
        switch self {
        case .queued: return L10n.t("В очереди")
        case .processing: return L10n.t("Обработка…")
        case .done: return L10n.t("Готово")
        case .failed: return L10n.t("Ошибка")
        }
    }

    var symbolName: String {
        switch self {
        case .queued: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// A single image in the sidebar queue. Images are kept as upright `CGImage`s;
/// `NSImage.size` is never used for pixel math.
@MainActor
final class ImageItem: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let displayName: String
    let pixelSize: CGSize
    let formatLabel: String
    let fileSizeBytes: Int64?
    let original: CGImage
    let thumbnail: NSImage

    @Published var result: CGImage?
    @Published var status: ItemStatus = .queued
    @Published var errorMessage: String?
    @Published var optionsUsed: UpscaleOptions?
    @Published var processedAt: Date?
    @Published var progressFraction: Double = 0

    init(loaded: LoadedImage) {
        self.sourceURL = loaded.url
        self.displayName = loaded.url.lastPathComponent
        self.pixelSize = loaded.pixelSize
        self.formatLabel = loaded.formatLabel
        self.fileSizeBytes = loaded.fileSizeBytes
        self.original = loaded.image
        self.thumbnail = loaded.thumbnail
    }

    var resultSize: CGSize? {
        guard let result else { return nil }
        return CGSize(width: result.width, height: result.height)
    }

    var displayImage: CGImage {
        result ?? original
    }

    var displaySize: CGSize {
        resultSize ?? pixelSize
    }

    var sourceSizeText: String {
        Formatting.pixelSize(pixelSize)
    }

    var resultSizeText: String {
        guard let resultSize else { return "—" }
        return Formatting.pixelSize(resultSize)
    }

    var compactSizeText: String {
        Formatting.compactPixelSize(pixelSize)
    }

    var fileSizeText: String {
        guard let fileSizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var suggestedExportSuffix: String {
        let scale = optionsUsed?.scale ?? .x2
        return "@\(scale.rawValue)x"
    }
}
