import Foundation
import CoreGraphics
import CoreImage

/// Image conversion helpers shared by the inference pipeline and the Lanczos
/// fallback. All buffers are 8-bit RGBA, top-down, in the sRGB color space.
enum ImageCodec {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let rgbaBitmapInfo: UInt32 =
        CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    private static let sharedCIContext: CIContext = {
        CIContext(options: [
            .workingColorSpace: sRGB,
            .outputColorSpace: sRGB,
            .cacheIntermediates: false,
        ])
    }()

    struct DecodedImage {
        var pixels: [UInt8]
        let width: Int
        let height: Int
        let hasTransparency: Bool
    }

    // MARK: - Decoding

    static func decode(_ image: CGImage) throws -> DecodedImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw UpscaleError.unsupportedImage
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow, byteCount > 0 else {
            throw UpscaleError.unsupportedImage
        }

        var pixels = [UInt8](repeating: 0, count: byteCount)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGB,
                bitmapInfo: rgbaBitmapInfo
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            throw UpscaleError.imageDecodingFailed(L10n.t("Не удалось создать RGBA-буфер."))
        }

        let sourceHasAlphaChannel: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            sourceHasAlphaChannel = false
        default:
            sourceHasAlphaChannel = true
        }

        var hasTransparency = false
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            let count = buffer.count
            if sourceHasAlphaChannel {
                var index = 0
                while index < count {
                    let alpha = Int(base[index + 3])
                    if alpha != 255 {
                        hasTransparency = true
                        if alpha == 0 {
                            base[index] = 0
                            base[index + 1] = 0
                            base[index + 2] = 0
                        } else {
                            // The context produced premultiplied RGBA; the model
                            // expects straight (unpremultiplied) RGB.
                            base[index] = UInt8(min(255, (Int(base[index]) * 255 + alpha / 2) / alpha))
                            base[index + 1] = UInt8(min(255, (Int(base[index + 1]) * 255 + alpha / 2) / alpha))
                            base[index + 2] = UInt8(min(255, (Int(base[index + 2]) * 255 + alpha / 2) / alpha))
                        }
                    }
                    index += 4
                }
            }
        }

        return DecodedImage(
            pixels: pixels,
            width: width,
            height: height,
            hasTransparency: hasTransparency
        )
    }

    // MARK: - Encoding

    static func makeImage(
        pixels: [UInt8],
        width: Int,
        height: Int,
        hasAlpha: Bool
    ) throws -> CGImage {
        guard width > 0, height > 0 else {
            throw UpscaleError.unsupportedImage
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow, pixels.count == byteCount else {
            throw UpscaleError.unsupportedImage
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | (hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue
                        : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: sRGB,
            bitmapInfo: bitmapInfo
        ), let destination = context.data else {
            throw UpscaleError.exportFailed(L10n.t("Не удалось создать выходной буфер."))
        }
        pixels.withUnsafeBytes { source in
            if let base = source.baseAddress {
                memcpy(destination, base, byteCount)
            }
        }
        guard let image = context.makeImage() else {
            throw UpscaleError.exportFailed(L10n.t("Не удалось создать CGImage."))
        }
        return image
    }

    /// Premultiplies an opaque RGB image with a separately scaled alpha channel.
    static func recombine(
        rgb: CGImage,
        alpha: [UInt8],
        width: Int,
        height: Int
    ) throws -> CGImage {
        var decoded = try decode(rgb)
        guard decoded.width == width, decoded.height == height,
              alpha.count == width * height else {
            throw UpscaleError.inferenceFailed(L10n.t("Несовпадение размеров RGB и альфа-канала."))
        }

        decoded.pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for i in 0..<alpha.count {
                let a = Int(alpha[i])
                let offset = i * 4
                if a == 255 {
                    base[offset + 3] = 255
                } else if a == 0 {
                    base[offset] = 0
                    base[offset + 1] = 0
                    base[offset + 2] = 0
                    base[offset + 3] = 0
                } else {
                    base[offset] = UInt8((Int(base[offset]) * a + 127) / 255)
                    base[offset + 1] = UInt8((Int(base[offset + 1]) * a + 127) / 255)
                    base[offset + 2] = UInt8((Int(base[offset + 2]) * a + 127) / 255)
                    base[offset + 3] = UInt8(a)
                }
            }
        }

        return try makeImage(
            pixels: decoded.pixels,
            width: width,
            height: height,
            hasAlpha: true
        )
    }

    // MARK: - Alpha scaling

    /// Scales the source alpha channel with Core Image's Lanczos filter.
    static func scaledAlpha(from image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        guard image.width > 0, image.height > 0, width > 0, height > 0 else {
            throw UpscaleError.unsupportedImage
        }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !overflow, !byteOverflow else {
            throw UpscaleError.unsupportedImage
        }

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw UpscaleError.inferenceFailed(L10n.t("Фильтр Lanczos недоступен."))
        }
        // Clamping the input extent replicates edge pixels. Without it Core
        // Image would sample transparent black outside the image and fade the
        // outer border (including alpha) even for fully opaque source pixels.
        let source = CIImage(cgImage: image).clampedToExtent()
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(Double(width) / Double(image.width), forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else {
            throw UpscaleError.inferenceFailed(L10n.t("Не удалось масштабировать альфа-канал."))
        }

        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        let cropped = output.cropped(to: targetRect)
        guard let scaled = sharedCIContext.createCGImage(cropped, from: targetRect) else {
            throw UpscaleError.inferenceFailed(L10n.t("Не удалось обработать альфа-канал."))
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGB,
                bitmapInfo: rgbaBitmapInfo
            ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.setBlendMode(.copy)
            context.draw(scaled, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            throw UpscaleError.inferenceFailed(L10n.t("Не удалось сформировать альфа-канал."))
        }

        var alpha = [UInt8](repeating: 255, count: pixelCount)
        bytes.withUnsafeBufferPointer { source in
            alpha.withUnsafeMutableBufferPointer { destination in
                for i in 0..<pixelCount {
                    destination[i] = source[i * 4 + 3]
                }
            }
        }
        return alpha
    }

    // MARK: - Lanczos fallback

    static func lanczosScale(_ image: CGImage, scale: Int, forceOpaque: Bool) throws -> CGImage {
        guard image.width > 0, image.height > 0, scale == 2 || scale == 4 else {
            throw UpscaleError.unsupportedImage
        }
        let (targetWidth, widthOverflow) = image.width.multipliedReportingOverflow(by: scale)
        let (targetHeight, heightOverflow) = image.height.multipliedReportingOverflow(by: scale)
        guard !widthOverflow, !heightOverflow else {
            throw UpscaleError.unsupportedImage
        }
        let (_, pixelOverflow) = targetWidth.multipliedReportingOverflow(by: targetHeight)
        guard !pixelOverflow else {
            throw UpscaleError.unsupportedImage
        }

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw UpscaleError.inferenceFailed(L10n.t("Фильтр Lanczos недоступен."))
        }
        let source = CIImage(cgImage: image).clampedToExtent()
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(Double(scale), forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else {
            throw UpscaleError.inferenceFailed(L10n.t("Не удалось выполнить Lanczos-масштабирование."))
        }

        let targetRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        let cropped = output.cropped(to: targetRect)
        guard let scaled = sharedCIContext.createCGImage(cropped, from: targetRect) else {
            throw UpscaleError.inferenceFailed(L10n.t("Не удалось построить Lanczos-изображение."))
        }

        let (pixelCount, countOverflow) = targetWidth.multipliedReportingOverflow(by: targetHeight)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !countOverflow, !byteOverflow else {
            throw UpscaleError.unsupportedImage
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: sRGB,
                bitmapInfo: rgbaBitmapInfo
            ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            context.interpolationQuality = .high
            context.setBlendMode(.copy)
            context.draw(scaled, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard drew else {
            throw UpscaleError.inferenceFailed(L10n.t("Не удалось сформировать выходное изображение."))
        }

        var hasTransparency = false
        if forceOpaque {
            bytes.withUnsafeMutableBufferPointer { buffer in
                var index = 3
                while index < buffer.count {
                    buffer[index] = 255
                    index += 4
                }
            }
        } else {
            bytes.withUnsafeBufferPointer { buffer in
                var index = 3
                while index < buffer.count {
                    if buffer[index] != 255 {
                        hasTransparency = true
                        break
                    }
                    index += 4
                }
            }
        }

        return try makeImage(
            pixels: bytes,
            width: targetWidth,
            height: targetHeight,
            hasAlpha: hasTransparency
        )
    }

    // MARK: - JPEG

    /// JPEG has no alpha channel; composite transparent images onto white.
    static func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw UpscaleError.unsupportedImage
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else {
            throw UpscaleError.unsupportedImage
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGB,
                bitmapInfo: rgbaBitmapInfo
            ) else {
                return false
            }
            context.setFillColor(CGColor(colorSpace: sRGB, components: [1, 1, 1, 1])!)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            throw UpscaleError.exportFailed(L10n.t("Не удалось подготовить изображение для JPEG."))
        }
        return try makeImage(pixels: bytes, width: width, height: height, hasAlpha: false)
    }
}
