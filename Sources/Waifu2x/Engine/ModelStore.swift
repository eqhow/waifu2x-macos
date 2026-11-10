import Foundation
import CoreML

/// Locates the bundled waifu2x Core ML models and manages compiled-model caching.
///
/// The models ship as `.mlmodel` sources. Core ML needs a compiled `.mlmodelc`
/// directory, so we compile lazily and keep a per-user cache under
/// `~/Library/Application Support/Waifu2x/CompiledModels`.
final class ModelStore: @unchecked Sendable {
    static let shared = ModelStore()

    /// All ten UpConv7 2x models that ship with the app.
    static let allModelNames: [String] = [
        "up_anime_scale2x_model",
        "up_anime_noise0_scale2x_model",
        "up_anime_noise1_scale2x_model",
        "up_anime_noise2_scale2x_model",
        "up_anime_noise3_scale2x_model",
        "up_photo_scale2x_model",
        "up_photo_noise0_scale2x_model",
        "up_photo_noise1_scale2x_model",
        "up_photo_noise2_scale2x_model",
        "up_photo_noise3_scale2x_model",
    ]

    private let directoryLock = NSLock()
    private var resolvedDirectory: URL?
    private var didResolveDirectory = false

    private let modelLock = NSLock()
    private var loadedModels: [String: MLModel] = [:]

    private init() {}

    // MARK: - Discovery

    /// Directory containing the ten `.mlmodel` files, or nil when unavailable.
    var modelsDirectory: URL? {
        directoryLock.lock()
        defer { directoryLock.unlock() }
        if didResolveDirectory {
            return resolvedDirectory
        }
        didResolveDirectory = true
        resolvedDirectory = Self.findModelsDirectory()
        return resolvedDirectory
    }

    /// Names of the bundled models that are present on disk.
    var availableModelNames: [String] {
        guard let directory = modelsDirectory else { return [] }
        return Self.allModelNames.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0 + ".mlmodel").path)
        }
    }

    /// Fast snapshot of model availability. Does not compile anything.
    func makeStatus() -> EngineStatus {
        let available = availableModelNames
        if available.count == Self.allModelNames.count {
            return EngineStatus(
                kind: .coreML,
                title: "waifu2x · Core ML",
                detail: L10n.t("10 моделей UpConv7 · 2×"),
                isReady: true
            )
        }

        let detail: String
        if modelsDirectory == nil {
            detail = L10n.t("Модели не найдены · Lanczos fallback")
        } else if available.isEmpty {
            detail = L10n.f("%ld из 10 моделей · Lanczos fallback", available.count)
        } else {
            detail = L10n.f("%ld из 10 моделей · Lanczos fallback", available.count)
        }
        return EngineStatus(
            kind: .fallback,
            title: "waifu2x · Lanczos",
            detail: detail,
            isReady: true
        )
    }

    /// Compiled-model cache location used by the engine.
    static func compiledModelsDirectory() -> URL? {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Waifu2x", isDirectory: true)
            .appendingPathComponent("CompiledModels", isDirectory: true)
    }

    // MARK: - Loading / compiling

    /// Returns a loaded model, compiling it on first use. Never falls back.
    func model(named name: String) throws -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }

        if let cached = loadedModels[name] {
            return cached
        }

        guard let directory = modelsDirectory else {
            throw UpscaleError.modelUnavailable(name)
        }
        let sourceURL = directory.appendingPathComponent(name + ".mlmodel")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw UpscaleError.modelUnavailable(name)
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let fileManager = FileManager.default
        guard let cacheDirectory = Self.compiledModelsDirectory() else {
            throw UpscaleError.modelCompilationFailed(L10n.t("Не удалось определить каталог кэша моделей."))
        }
        let cacheURL = cacheDirectory.appendingPathComponent(name + ".mlmodelc")

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            throw UpscaleError.modelCompilationFailed(L10n.f("Не удалось создать кэш моделей: %@", error.localizedDescription))
        }

        // Reuse a healthy cached compile.
        if fileManager.fileExists(atPath: cacheURL.path) {
            do {
                let cached = try MLModel(contentsOf: cacheURL, configuration: configuration)
                loadedModels[name] = cached
                return cached
            } catch {
                // Corrupt/incompatible cache: remove it and compile once from source.
                try? fileManager.removeItem(at: cacheURL)
            }
        }

        let compiledURL: URL
        do {
            compiledURL = try MLModel.compileModel(at: sourceURL)
        } catch {
            throw UpscaleError.modelCompilationFailed(
                "\(name): \(error.localizedDescription)"
            )
        }

        do {
            try Self.installCompiledModel(from: compiledURL, to: cacheURL, fileManager: fileManager)
            let model = try MLModel(contentsOf: cacheURL, configuration: configuration)
            loadedModels[name] = model
            return model
        } catch let error as UpscaleError {
            throw error
        } catch {
            throw UpscaleError.modelCompilationFailed(
                "\(name): \(error.localizedDescription)"
            )
        }
    }

    private static func installCompiledModel(
        from compiledURL: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).mlmodelc", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporary) }

        try fileManager.copyItem(at: compiledURL, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    // MARK: - Path candidates

    private static func findModelsDirectory() -> URL? {
        let fileManager = FileManager.default

        // An explicitly configured directory always wins (even when empty, so
        // missing-model fallback can be exercised deliberately).
        if let override = ProcessInfo.processInfo.environment["WAIFU2X_MODELS_DIR"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        var candidates: [URL] = []

        #if SWIFT_PACKAGE
        if let resourceURL = Bundle.module.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Models", isDirectory: true))
        }
        if let url = Bundle.module.url(forResource: "Models", withExtension: nil) {
            candidates.append(url)
        }
        #endif

        // Assembled .app (Support/build-app.sh copies the resource bundle into
        // Contents/Resources) and plain SwiftPM output directories.
        let resourceRoots: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ]
        for root in resourceRoots {
            guard let root else { continue }
            candidates.append(root
                .appendingPathComponent("Waifu2x_Waifu2x.bundle", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true))
            candidates.append(root.appendingPathComponent("Models", isDirectory: true))
        }

        // Running from a checkout (CLI, harness, tests).
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Sources/Waifu2x/Resources/Models", isDirectory: true))

        // Source-file relative path covers binaries launched from elsewhere.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Engine
            .deletingLastPathComponent() // Waifu2x
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // project root
        candidates.append(sourceRoot
            .appendingPathComponent("Sources/Waifu2x/Resources/Models", isDirectory: true))

        // Walk up from the executable (e.g. .build/debug/Waifu2x -> project root).
        if var executableDirectory = Bundle.main.executableURL?
            .resolvingSymlinksInPath()
            .deletingLastPathComponent() {
            for _ in 0..<6 {
                candidates.append(executableDirectory
                    .appendingPathComponent("Sources/Waifu2x/Resources/Models", isDirectory: true))
                let parent = executableDirectory.deletingLastPathComponent()
                if parent.path == executableDirectory.path { break }
                executableDirectory = parent
            }
        }

        var seen = Set<String>()
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            guard fileManager.fileExists(atPath: standardized.path) else { continue }
            let containsModel = allModelNames.contains {
                fileManager.fileExists(atPath: standardized.appendingPathComponent($0 + ".mlmodel").path)
            }
            if containsModel {
                return standardized
            }
        }
        return nil
    }
}
