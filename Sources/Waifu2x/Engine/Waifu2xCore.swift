import Foundation
import CoreML
import CoreGraphics

/// Core UpConv7 tiling pipeline.
///
/// The models take a fixed 3x156x156 (CHW, 0...1) input and produce 3x284x284,
/// i.e. a 142 px core plus 7 px of context on each side, upscaled 2x.
enum Waifu2xCore {
    static let coreTile = 142
    static let contextPixels = 7
    static let inputTile = 156  // 142 + 2 * 7
    static let outputTile = 284 // 142 * 2
    static let inputTilePlane = inputTile * inputTile
    static let outputTilePlane = outputTile * outputTile

    struct Result {
        let image: CGImage
        let hasTransparency: Bool
    }

    private final class InputProvider: MLFeatureProvider {
        let array: MLMultiArray

        init(_ array: MLMultiArray) {
            self.array = array
        }

        var featureNames: Set<String> { ["input"] }

        func featureValue(for featureName: String) -> MLFeatureValue? {
            guard featureName == "input" else { return nil }
            return MLFeatureValue(multiArray: array)
        }
    }

    static func upscale2x(
        image: CGImage,
        model: MLModel,
        cancellation: CancellationToken,
        progress: (_ completedTiles: Int, _ totalTiles: Int) -> Void
    ) throws -> Result {
        if cancellation.isCancelled {
            throw UpscaleError.cancelled
        }

        let decoded = try ImageCodec.decode(image)
        let sourceWidth = decoded.width
        let sourceHeight = decoded.height

        let (outputWidth, widthOverflow) = sourceWidth.multipliedReportingOverflow(by: 2)
        let (outputHeight, heightOverflow) = sourceHeight.multipliedReportingOverflow(by: 2)
        guard !widthOverflow, !heightOverflow else {
            throw UpscaleError.unsupportedImage
        }
        let (outputPixelCount, outputPixelOverflow) = outputWidth.multipliedReportingOverflow(by: outputHeight)
        let (outputByteCount, outputByteOverflow) = outputPixelCount.multipliedReportingOverflow(by: 4)
        guard !outputPixelOverflow, !outputByteOverflow, outputByteCount > 0 else {
            throw UpscaleError.unsupportedImage
        }

        // Edge-replicate tiny images up to one core tile first, then add the
        // 7 px context border used by the network.
        let paddedWidth = max(sourceWidth, coreTile)
        let paddedHeight = max(sourceHeight, coreTile)
        let (expandedWidth, expandedWidthOverflow) = paddedWidth.addingReportingOverflow(2 * contextPixels)
        let (expandedHeight, expandedHeightOverflow) = paddedHeight.addingReportingOverflow(2 * contextPixels)
        guard !expandedWidthOverflow, !expandedHeightOverflow else {
            throw UpscaleError.unsupportedImage
        }
        let (expandedPixelCount, expandedPixelOverflow) = expandedWidth.multipliedReportingOverflow(by: expandedHeight)
        let (expandedByteCount, expandedByteOverflow) = expandedPixelCount.multipliedReportingOverflow(by: 3)
        guard !expandedPixelOverflow, !expandedByteOverflow, expandedByteCount > 0 else {
            throw UpscaleError.unsupportedImage
        }

        let xOrigins = tileOrigins(for: paddedWidth)
        let yOrigins = tileOrigins(for: paddedHeight)
        let totalTiles = xOrigins.count * yOrigins.count
        guard totalTiles > 0 else {
            throw UpscaleError.unsupportedImage
        }

        // Planar RGB, expanded with replicated borders. Keeping this as UInt8
        // avoids huge intermediate Float allocations for large 4× pass 2 runs.
        var expanded = [UInt8](repeating: 0, count: expandedByteCount)
        expanded.withUnsafeMutableBufferPointer { destination in
            decoded.pixels.withUnsafeBufferPointer { source in
                guard let dst = destination.baseAddress, let src = source.baseAddress else { return }
                let planeSize = expandedPixelCount
                let red = dst
                let green = dst + planeSize
                let blue = dst + planeSize * 2

                for y in 0..<expandedHeight {
                    let paddedY = min(max(y - contextPixels, 0), paddedHeight - 1)
                    let sourceY = min(paddedY, sourceHeight - 1)
                    let sourceRow = sourceY * sourceWidth * 4
                    let destinationRow = y * expandedWidth
                    for x in 0..<expandedWidth {
                        let paddedX = min(max(x - contextPixels, 0), paddedWidth - 1)
                        let sourceX = min(paddedX, sourceWidth - 1)
                        let sourceIndex = sourceRow + sourceX * 4
                        let destinationIndex = destinationRow + x
                        red[destinationIndex] = src[sourceIndex]
                        green[destinationIndex] = src[sourceIndex + 1]
                        blue[destinationIndex] = src[sourceIndex + 2]
                    }
                }
            }
        }

        let shape: [NSNumber] = [
            3,
            NSNumber(value: inputTile),
            NSNumber(value: inputTile),
        ]
        let inputArray: MLMultiArray
        do {
            inputArray = try MLMultiArray(shape: shape, dataType: .float32)
        } catch {
            throw UpscaleError.inferenceFailed(L10n.f("Не удалось выделить входной массив: %@", error.localizedDescription))
        }
        guard inputArray.count == 3 * inputTilePlane else {
            throw UpscaleError.inferenceFailed(L10n.t("Неожиданный размер входного массива."))
        }
        let inputPointer = inputArray.dataPointer.bindMemory(
            to: Float.self,
            capacity: 3 * inputTilePlane
        )
        let provider = InputProvider(inputArray)

        var outputPixels = [UInt8](repeating: 255, count: outputByteCount)
        var completedTiles = 0
        let scaleFactor = Float(1.0 / 255.0)

        try expanded.withUnsafeBufferPointer { expandedBuffer in
            try outputPixels.withUnsafeMutableBufferPointer { outputBuffer in
                guard let expandedBase = expandedBuffer.baseAddress,
                      let outputBase = outputBuffer.baseAddress else {
                    throw UpscaleError.inferenceFailed(L10n.t("Не удалось получить буферы изображения."))
                }

                for originY in yOrigins {
                    for originX in xOrigins {
                        if cancellation.isCancelled {
                            throw UpscaleError.cancelled
                        }

                        try autoreleasepool {
                            // Gather the 156×156 RGB tile into the reusable CHW array.
                            for channel in 0..<3 {
                                let sourcePlane = expandedBase
                                    + channel * expandedPixelCount
                                    + originY * expandedWidth
                                    + originX
                                let destinationPlane = inputPointer + channel * inputTilePlane
                                for row in 0..<inputTile {
                                    let sourceRow = sourcePlane + row * expandedWidth
                                    let destinationRow = destinationPlane + row * inputTile
                                    for column in 0..<inputTile {
                                        destinationRow[column] = Float(sourceRow[column]) * scaleFactor
                                    }
                                }
                            }

                            let prediction: MLFeatureProvider
                            do {
                                prediction = try model.prediction(from: provider)
                            } catch {
                                throw UpscaleError.inferenceFailed(error.localizedDescription)
                            }
                            guard let output = prediction.featureValue(for: "conv7")?.multiArrayValue else {
                                throw UpscaleError.inferenceFailed(L10n.t("Модель не вернула выход «conv7»."))
                            }
                            try paste(
                                output: output,
                                destination: outputBase,
                                destinationWidth: outputWidth,
                                destinationHeight: outputHeight,
                                originX: originX * 2,
                                originY: originY * 2
                            )
                        }

                        completedTiles += 1
                        progress(completedTiles, totalTiles)
                    }
                }
            }
        }

        let result = try ImageCodec.makeImage(
            pixels: outputPixels,
            width: outputWidth,
            height: outputHeight,
            hasAlpha: false
        )
        return Result(image: result, hasTransparency: decoded.hasTransparency)
    }

    // MARK: - Tiles

    /// Origins across one axis: 0, 142, 284, … and an overlapping edge tile
    /// when the last step would leave a gap. A divisible axis gets no duplicate.
    private static func tileOrigins(for size: Int) -> [Int] {
        guard size > coreTile else { return [0] }
        var origins = Array(stride(from: 0, to: size - coreTile, by: coreTile))
        origins.append(size - coreTile)
        return origins
    }

    // MARK: - Output

    private static func paste(
        output: MLMultiArray,
        destination: UnsafeMutablePointer<UInt8>,
        destinationWidth: Int,
        destinationHeight: Int,
        originX: Int,
        originY: Int
    ) throws {
        let shape = output.shape.map { $0.intValue }
        guard shape.count >= 3 else {
            throw UpscaleError.inferenceFailed(L10n.t("Неожиданная размерность выхода модели."))
        }
        let base = shape.count - 3
        guard shape[base] == 3,
              shape[base + 1] == outputTile,
              shape[base + 2] == outputTile else {
            throw UpscaleError.inferenceFailed(L10n.f("Неожиданная форма выхода модели: %@.", String(describing: shape)))
        }

        let strides = output.strides.map { $0.intValue }
        let channelStride = strides[base]
        let rowStride = strides[base + 1]
        let columnStride = strides[base + 2]

        let copyWidth = min(outputTile, destinationWidth - originX)
        let copyHeight = min(outputTile, destinationHeight - originY)
        guard copyWidth > 0, copyHeight > 0 else { return }

        switch output.dataType {
        case .double:
            let pointer = output.dataPointer.assumingMemoryBound(to: Double.self)
            writePixels(
                pointer: pointer,
                channelStride: channelStride,
                rowStride: rowStride,
                columnStride: columnStride,
                destination: destination,
                destinationWidth: destinationWidth,
                originX: originX,
                originY: originY,
                copyWidth: copyWidth,
                copyHeight: copyHeight
            )
        case .float32:
            let pointer = output.dataPointer.assumingMemoryBound(to: Float.self)
            writePixels(
                pointer: pointer,
                channelStride: channelStride,
                rowStride: rowStride,
                columnStride: columnStride,
                destination: destination,
                destinationWidth: destinationWidth,
                originX: originX,
                originY: originY,
                copyWidth: copyWidth,
                copyHeight: copyHeight
            )
        case .float16:
            let pointer = output.dataPointer.assumingMemoryBound(to: Float16.self)
            writePixels(
                pointer: pointer,
                channelStride: channelStride,
                rowStride: rowStride,
                columnStride: columnStride,
                destination: destination,
                destinationWidth: destinationWidth,
                originX: originX,
                originY: originY,
                copyWidth: copyWidth,
                copyHeight: copyHeight
            )
        default:
            throw UpscaleError.inferenceFailed(L10n.f("Неподдерживаемый тип выхода модели: %ld.", output.dataType.rawValue))
        }
    }

    private static func writePixels<T: BinaryFloatingPoint>(
        pointer: UnsafePointer<T>,
        channelStride: Int,
        rowStride: Int,
        columnStride: Int,
        destination: UnsafeMutablePointer<UInt8>,
        destinationWidth: Int,
        originX: Int,
        originY: Int,
        copyWidth: Int,
        copyHeight: Int
    ) {
        let red = pointer
        let green = pointer + channelStride
        let blue = pointer + channelStride * 2

        for row in 0..<copyHeight {
            let sourceRowOffset = row * rowStride
            let destinationRow = destination
                + ((originY + row) * destinationWidth + originX) * 4
            for column in 0..<copyWidth {
                let sourceOffset = sourceRowOffset + column * columnStride
                let destinationOffset = column * 4
                destinationRow[destinationOffset] = byte(from: red[sourceOffset])
                destinationRow[destinationOffset + 1] = byte(from: green[sourceOffset])
                destinationRow[destinationOffset + 2] = byte(from: blue[sourceOffset])
                // Alpha was pre-filled with 255; only RGB is produced here.
            }
        }
    }

    @inline(__always)
    private static func byte<T: BinaryFloatingPoint>(from value: T) -> UInt8 {
        let float = Float(value)
        if !(float > 0) { return 0 } // also catches NaN
        if float >= 1 { return 255 }
        return UInt8(float * 255 + 0.5)
    }
}
