import Foundation
import CoreGraphics

/// Public entry point for the waifu2x engine.
///
/// All inference work happens on a private serial queue (Core ML models are not
/// safe for concurrent prediction). The service reuses compiled models and
/// loaded `MLModel` instances across jobs.
public final class ProcessingService: @unchecked Sendable {
    public static let shared = ProcessingService()

    private let workQueue = DispatchQueue(
        label: "com.waifu2x.processing",
        qos: .userInitiated
    )
    private let statusQueue = DispatchQueue(
        label: "com.waifu2x.status",
        qos: .userInitiated
    )
    private let statusLock = NSLock()
    private let modelStore = ModelStore.shared
    private var storedStatus: EngineStatus

    private init() {
        storedStatus = modelStore.makeStatus()
    }

    /// Thread-safe snapshot of the current engine status.
    public var status: EngineStatus {
        statusLock.lock()
        defer { statusLock.unlock() }
        return storedStatus
    }

    /// Validates the bundled models without compiling them. Runs off-main.
    public func prepare() async -> EngineStatus {
        await withCheckedContinuation { continuation in
            statusQueue.async {
                let status = self.modelStore.makeStatus()
                self.setStatus(status)
                continuation.resume(returning: status)
            }
        }
    }

    /// Upscales an image. The completion runs on the service's serial queue;
    /// callers that need main-thread updates should hop themselves.
    public func upscale(
        _ image: CGImage,
        options: UpscaleOptions,
        progress: @escaping @Sendable (UpscaleProgress) -> Void,
        cancellation: CancellationToken
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                do {
                    let result = try self.performUpscale(
                        image,
                        options: options,
                        progress: progress,
                        cancellation: cancellation
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Implementation

    private func setStatus(_ status: EngineStatus) {
        statusLock.lock()
        storedStatus = status
        statusLock.unlock()
    }

    private func performUpscale(
        _ image: CGImage,
        options: UpscaleOptions,
        progress: @escaping @Sendable (UpscaleProgress) -> Void,
        cancellation: CancellationToken
    ) throws -> CGImage {
        let width = image.width
        let height = image.height
        let scale = options.scale.rawValue
        guard width > 0, height > 0 else {
            throw UpscaleError.unsupportedImage
        }

        let (outputWidth, widthOverflow) = width.multipliedReportingOverflow(by: scale)
        let (outputHeight, heightOverflow) = height.multipliedReportingOverflow(by: scale)
        let (outputPixels, pixelOverflow) = outputWidth.multipliedReportingOverflow(by: outputHeight)
        let (_, byteOverflow) = outputPixels.multipliedReportingOverflow(by: 4)
        guard !widthOverflow, !heightOverflow, !pixelOverflow, !byteOverflow else {
            throw UpscaleError.unsupportedImage
        }

        if cancellation.isCancelled {
            throw UpscaleError.cancelled
        }

        let available = Set(modelStore.availableModelNames)

        // No bundled models at all: transparent Lanczos fallback.
        if available.isEmpty {
            let fallbackStatus = modelStore.makeStatus()
            setStatus(fallbackStatus)
            let detail = "Lanczos \(scale)×"
            progress(UpscaleProgress(
                fraction: 0,
                pass: 1,
                passCount: 1,
                detail: detail
            ))
            let fallback = try LanczosEngine.upscale(
                image,
                scale: scale,
                cancellation: cancellation
            ) { fraction in
                progress(UpscaleProgress(
                    fraction: fraction,
                    pass: 1,
                    passCount: 1,
                    detail: detail
                ))
            }
            progress(UpscaleProgress(
                fraction: 1,
                pass: 1,
                passCount: 1,
                detail: L10n.t("Готово")
            ))
            return fallback
        }

        let requiredModels: [String]
        if options.passCount > 1 {
            requiredModels = [options.primaryModelName, options.secondaryModelName]
        } else {
            requiredModels = [options.primaryModelName]
        }
        for name in requiredModels where !available.contains(name) {
            throw UpscaleError.modelUnavailable(name)
        }

        var current = image
        var sourceHasTransparency = false

        for passIndex in 0..<options.passCount {
            if cancellation.isCancelled {
                throw UpscaleError.cancelled
            }

            let passNumber = passIndex + 1
            let baseFraction = Double(passIndex) / Double(options.passCount)
            let modelName = passIndex == 0
                ? options.primaryModelName
                : options.secondaryModelName

            progress(UpscaleProgress(
                fraction: baseFraction,
                pass: passNumber,
                passCount: options.passCount,
                detail: L10n.t("Подготовка модели…")
            ))

            let model = try modelStore.model(named: modelName)

            if cancellation.isCancelled {
                throw UpscaleError.cancelled
            }

            let result = try Waifu2xCore.upscale2x(
                image: current,
                model: model,
                cancellation: cancellation
            ) { completedTiles, totalTiles in
                let passFraction = totalTiles > 0
                    ? Double(completedTiles) / Double(totalTiles)
                    : 1
                let overall = (Double(passIndex) + passFraction) / Double(options.passCount)
                progress(UpscaleProgress(
                    fraction: overall,
                    pass: passNumber,
                    passCount: options.passCount,
                    detail: L10n.f("Проход %ld из %ld · тайл %ld/%ld", passNumber, options.passCount, completedTiles, totalTiles)
                ))
            }

            if passIndex == 0 {
                sourceHasTransparency = result.hasTransparency
            }
            current = result.image
        }

        if sourceHasTransparency {
            if cancellation.isCancelled {
                throw UpscaleError.cancelled
            }
            let alpha = try ImageCodec.scaledAlpha(
                from: image,
                width: outputWidth,
                height: outputHeight
            )
            if cancellation.isCancelled {
                throw UpscaleError.cancelled
            }
            current = try ImageCodec.recombine(
                rgb: current,
                alpha: alpha,
                width: outputWidth,
                height: outputHeight
            )
        }

        progress(UpscaleProgress(
            fraction: 1,
            pass: options.passCount,
            passCount: options.passCount,
            detail: L10n.t("Готово")
        ))
        return current
    }
}
