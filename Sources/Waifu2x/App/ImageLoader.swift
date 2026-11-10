import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LoadedImage {
    let url: URL
    let image: CGImage
    let thumbnail: NSImage
    let pixelSize: CGSize
    let formatLabel: String
    let fileSizeBytes: Int64?
}

enum ImageLoaderError: LocalizedError {
    case notAnImage
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notAnImage: return L10n.t("Файл не является изображением.")
        case .unreadable: return L10n.t("Не удалось прочитать изображение.")
        }
    }
}

enum ImageLoader {
    private static let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    static func isImageFile(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let type = values.contentType {
            return type.conforms(to: .image)
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .image)
        }
        return false
    }

    static func load(url: URL) throws -> LoadedImage {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageLoaderError.unreadable
        }

        guard CGImageSourceGetCount(source) > 0 else {
            throw ImageLoaderError.unreadable
        }

        let typeIdentifier = CGImageSourceGetType(source) as String?
        if let typeIdentifier, let type = UTType(typeIdentifier), !type.conforms(to: .image) {
            throw ImageLoaderError.notAnImage
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1

        guard let raw = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else {
            throw ImageLoaderError.unreadable
        }

        let upright = try applyOrientation(raw, orientation: orientation)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 132,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) ?? upright
        let thumbnail = NSImage(
            cgImage: thumbnailCG,
            size: NSSize(width: thumbnailCG.width, height: thumbnailCG.height)
        )

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)

        return LoadedImage(
            url: url,
            image: upright,
            thumbnail: thumbnail,
            pixelSize: CGSize(width: upright.width, height: upright.height),
            formatLabel: formatLabel(for: typeIdentifier),
            fileSizeBytes: fileSize
        )
    }

    private static func applyOrientation(_ image: CGImage, orientation: UInt32) throws -> CGImage {
        guard orientation != 1 else { return image }
        let oriented = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
        guard let output = ciContext.createCGImage(oriented, from: oriented.extent) else {
            throw ImageLoaderError.unreadable
        }
        return output
    }

    private static func formatLabel(for identifier: String?) -> String {
        guard let identifier, let type = UTType(identifier) else { return L10n.t("Изображение") }
        if type.conforms(to: .png) { return "PNG" }
        if type.conforms(to: .jpeg) { return "JPEG" }
        if type.conforms(to: .heic) || identifier.lowercased().contains("heic") { return "HEIC" }
        if type.conforms(to: .tiff) { return "TIFF" }
        if type.conforms(to: .webP) { return "WebP" }
        if type.conforms(to: .gif) { return "GIF" }
        if type.conforms(to: .bmp) { return "BMP" }
        return type.preferredFilenameExtension?.uppercased() ?? L10n.t("Изображение")
    }
}
