import Foundation
import CoreGraphics

/// High-quality Core Image Lanczos fallback used when the Core ML models are
/// not available (or when the CLI is asked for the fast engine).
enum LanczosEngine {
    static func upscale(
        _ image: CGImage,
        scale: Int,
        cancellation: CancellationToken,
        progress: (_ fraction: Double) -> Void
    ) throws -> CGImage {
        guard image.width > 0, image.height > 0, scale == 2 || scale == 4 else {
            throw UpscaleError.unsupportedImage
        }
        if cancellation.isCancelled {
            throw UpscaleError.cancelled
        }

        // Detecting transparency up front lets us keep truly opaque sources
        // opaque: Core Image's Lanczos sampling can otherwise soften the alpha
        // at the outer image border even when the source is 100% opaque.
        let decoded = try ImageCodec.decode(image)

        progress(0)
        let result = try ImageCodec.lanczosScale(
            image,
            scale: scale,
            forceOpaque: !decoded.hasTransparency
        )

        if cancellation.isCancelled {
            throw UpscaleError.cancelled
        }
        progress(1)
        return result
    }
}
