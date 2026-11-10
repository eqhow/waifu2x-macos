import Foundation
import CoreGraphics

// MARK: - Upscale options
//
// Public contract shared by the UI and the inference engine.
// Keep this file free of UI/AppKit imports.

public struct UpscaleOptions: Hashable, Codable, Sendable {
    public enum Style: String, CaseIterable, Identifiable, Codable, Sendable {
        case anime
        case photo

        public var id: String { rawValue }

        /// Base model prefix, e.g. "up_anime".
        var modelPrefix: String { "up_\(rawValue)" }
    }

    public enum Denoise: Int, CaseIterable, Identifiable, Codable, Sendable {
        case off = -1
        case minimal = 0
        case low = 1
        case medium = 2
        case high = 3

        public var id: Int { rawValue }

        /// e.g. "noise1"; nil means the plain scale2x model.
        public var modelInfix: String? {
            self == .off ? nil : "noise\(rawValue)"
        }
    }

    public enum Scale: Int, CaseIterable, Identifiable, Codable, Sendable {
        case x2 = 2
        case x4 = 4

        public var id: Int { rawValue }
        public var title: String { "\(rawValue)×" }
    }

    public var style: Style
    public var denoise: Denoise
    public var scale: Scale

    public init(style: Style = .anime, denoise: Denoise = .low, scale: Scale = .x2) {
        self.style = style
        self.denoise = denoise
        self.scale = scale
    }

    /// Primary 2x model, e.g. "up_anime_noise1_scale2x_model".
    public var primaryModelName: String {
        var name = style.modelPrefix
        if let infix = denoise.modelInfix {
            name += "_\(infix)"
        }
        name += "_scale2x_model"
        return name
    }

    /// Second pass for 4×. The image has already been denoised once, so use the
    /// plain 2× model to avoid over-smoothing. e.g. "up_anime_scale2x_model".
    public var secondaryModelName: String {
        "\(style.modelPrefix)_scale2x_model"
    }

    /// Number of sequential 2× passes required by the selected scale.
    public var passCount: Int { scale == .x4 ? 2 : 1 }
}

// MARK: - Progress

public struct UpscaleProgress: Sendable {
    /// Overall progress in 0...1.
    public var fraction: Double
    /// 1-based pass index.
    public var pass: Int
    public var passCount: Int
    /// Short engine detail, e.g. "Модель · тайл 12/64".
    public var detail: String

    public init(fraction: Double, pass: Int = 1, passCount: Int = 1, detail: String = "") {
        self.fraction = min(max(fraction, 0), 1)
        self.pass = pass
        self.passCount = passCount
        self.detail = detail
    }
}

// MARK: - Engine status

public struct EngineStatus: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case coreML
        case fallback
        case unavailable
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    public var isReady: Bool

    public init(kind: Kind, title: String, detail: String, isReady: Bool) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.isReady = isReady
    }

    public static let preparing = EngineStatus(
        kind: .coreML,
        title: "Core ML",
        detail: L10n.t("Подготовка моделей…"),
        isReady: false
    )
}

// MARK: - Errors

public enum UpscaleError: LocalizedError, Sendable {
    case cancelled
    case unsupportedImage
    case imageDecodingFailed(String)
    case modelUnavailable(String)
    case modelCompilationFailed(String)
    case inferenceFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.t("Обработка отменена.")
        case .unsupportedImage:
            return L10n.t("Формат изображения не поддерживается.")
        case .imageDecodingFailed(let detail):
            return L10n.f("Не удалось прочитать изображение. %@", detail)
        case .modelUnavailable(let name):
            return L10n.f("Модель waifu2x «%@» не найдена.", name)
        case .modelCompilationFailed(let detail):
            return L10n.f("Не удалось подготовить модель Core ML. %@", detail)
        case .inferenceFailed(let detail):
            return L10n.f("Ошибка обработки. %@", detail)
        case .exportFailed(let detail):
            return L10n.f("Не удалось сохранить файл. %@", detail)
        }
    }
}

// MARK: - Cancellation

/// Thread-safe cancellation flag shared between the UI and the processing queue.
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

// MARK: - Processing service contract
//
// Implemented by Engine/ProcessingService.swift. The UI consumes exactly this API.
//
// public final class ProcessingService: @unchecked Sendable {
//     public static let shared: ProcessingService
//     public var status: EngineStatus { get }
//     public func prepare() async -> EngineStatus
//     public func upscale(
//         _ image: CGImage,
//         options: UpscaleOptions,
//         progress: @escaping @Sendable (UpscaleProgress) -> Void,
//         cancellation: CancellationToken
//     ) async throws -> CGImage
// }
//
// `prepare()` validates the bundled models and returns a ready/fallback status.
// `upscale(...)` runs on a private serial queue, reports progress off the main
// thread, checks the cancellation token between tiles, and throws
// `UpscaleError.cancelled` when cancelled.
