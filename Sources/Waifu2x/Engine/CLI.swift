import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Headless command-line interface. Dispatched from `Main.swift` before any
/// SwiftUI/AppKit application is created.
public enum CLI {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            return try runThrowing(arguments)
        } catch let error as CLIError {
            writeError(error.message)
            return 1
        } catch {
            writeError(error.localizedDescription)
            return 1
        }
    }

    // MARK: - Parsing

    private enum EngineChoice: String {
        case waifu2x
        case fast
    }

    private struct Options {
        var inputPath: String?
        var outputPath: String?
        var style: UpscaleOptions.Style = .anime
        var denoise: UpscaleOptions.Denoise = .low
        var scale: UpscaleOptions.Scale = .x2
        var engine: EngineChoice = .waifu2x
        var showHelp = false
        var showModels = false
    }

    private static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        func value(after flag: String) throws -> String {
            let next = index + 1
            guard next < arguments.count else {
                throw CLIError.usage("Не указано значение для \(flag).")
            }
            index = next
            return arguments[next]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                options.showHelp = true
            case "--models":
                options.showModels = true
            case "--upscale":
                options.inputPath = try value(after: argument)
            case "--output":
                options.outputPath = try value(after: argument)
            case "--style":
                let raw = try value(after: argument).lowercased()
                guard let style = UpscaleOptions.Style(rawValue: raw) else {
                    throw CLIError.usage("Неизвестный стиль «\(raw)». Используйте anime или photo.")
                }
                options.style = style
            case "--noise":
                let raw = try value(after: argument).lowercased()
                if raw == "none" {
                    options.denoise = .off
                } else if let value = Int(raw), let denoise = UpscaleOptions.Denoise(rawValue: value) {
                    options.denoise = denoise
                } else {
                    throw CLIError.usage("Неизвестный уровень шума «\(raw)». Используйте none, 0, 1, 2 или 3.")
                }
            case "--scale":
                let raw = try value(after: argument)
                guard let value = Int(raw), let scale = UpscaleOptions.Scale(rawValue: value) else {
                    throw CLIError.usage("Неизвестный масштаб «\(raw)». Используйте 2 или 4.")
                }
                options.scale = scale
            case "--engine":
                let raw = try value(after: argument).lowercased()
                guard let engine = EngineChoice(rawValue: raw) else {
                    throw CLIError.usage("Неизвестный движок «\(raw)». Используйте waifu2x или fast.")
                }
                options.engine = engine
            default:
                throw CLIError.usage("Неизвестный аргумент «\(argument)».")
            }
            index += 1
        }

        return options
    }

    // MARK: - Commands

    private static func runThrowing(_ arguments: [String]) throws -> Int32 {
        let options = try parse(arguments)

        if options.showHelp {
            print(helpText)
            return 0
        }
        if options.showModels {
            printModels()
            return 0
        }

        guard let inputPath = options.inputPath else {
            throw CLIError.usage("Не указан входной файл (--upscale <input>).")
        }
        guard let outputPath = options.outputPath else {
            throw CLIError.usage("Не указан выходной файл (--output <output>).")
        }

        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL

        let format = try outputFormat(for: outputURL)
        let image = try loadImage(at: inputURL)
        let upscaleOptions = UpscaleOptions(
            style: options.style,
            denoise: options.denoise,
            scale: options.scale
        )

        let start = CFAbsoluteTimeGetCurrent()
        let result: CGImage
        let engineTitle: String

        switch options.engine {
        case .fast:
            let cancellation = CancellationToken()
            result = try LanczosEngine.upscale(
                image,
                scale: options.scale.rawValue,
                cancellation: cancellation
            ) { _ in }
            engineTitle = "waifu2x · Lanczos (fast)"
        case .waifu2x:
            let service = ProcessingService.shared
            let cancellation = CancellationToken()
            result = try runAsync {
                try await service.upscale(
                    image,
                    options: upscaleOptions,
                    progress: { _ in },
                    cancellation: cancellation
                )
            }
            engineTitle = service.status.title
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let imageToWrite = format == .jpeg
            ? try ImageCodec.flattenedOnWhite(result)
            : result
        try write(imageToWrite, to: outputURL, format: format)

        print("Engine: \(engineTitle)")
        print("Input: \(image.width)×\(image.height)")
        print("Output: \(result.width)×\(result.height)")
        print(String(format: "Elapsed: %.2f s", elapsed))
        return 0
    }

    private static func printModels() {
        let service = ProcessingService.shared
        let status = service.status
        let fileManager = FileManager.default

        print("Engine: \(status.title)")
        print("Status: \(status.detail)")
        if let directory = ModelStore.shared.modelsDirectory {
            print("Models: \(directory.path)")
        } else {
            print("Models: not found")
        }
        if let cache = ModelStore.compiledModelsDirectory() {
            print("Cache: \(cache.path)")
        }

        var available = 0
        for name in ModelStore.allModelNames {
            let fileName = name + ".mlmodel"
            let exists: Bool
            if let directory = ModelStore.shared.modelsDirectory {
                exists = fileManager.fileExists(
                    atPath: directory.appendingPathComponent(fileName).path
                )
            } else {
                exists = false
            }
            if exists { available += 1 }
            print("  \(exists ? "[ok]" : "[missing]") \(fileName)")
        }
        print("Available: \(available)/\(ModelStore.allModelNames.count)")
    }

    // MARK: - Image loading / writing

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw UpscaleError.imageDecodingFailed("Не удалось открыть «\(url.lastPathComponent)».")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw UpscaleError.imageDecodingFailed("Формат файла не поддерживается.")
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let number = properties[kCGImagePropertyOrientation] as? NSNumber else {
            return image
        }
        let orientation = number.int32Value
        guard orientation != 1 else {
            return image
        }

        let oriented = CIImage(cgImage: image).oriented(forExifOrientation: orientation)
        let context = CIContext(options: [
            .workingColorSpace: ImageCodec.sRGB,
            .outputColorSpace: ImageCodec.sRGB,
        ])
        guard let result = context.createCGImage(oriented, from: oriented.extent) else {
            return image
        }
        return result
    }

    private enum OutputFormat {
        case png
        case jpeg

        var uti: CFString {
            switch self {
            case .png: return UTType.png.identifier as CFString
            case .jpeg: return UTType.jpeg.identifier as CFString
            }
        }
    }

    private static func outputFormat(for url: URL) throws -> OutputFormat {
        switch url.pathExtension.lowercased() {
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        default:
            throw CLIError.usage("Поддерживаются только выходные файлы PNG и JPEG.")
        }
    }

    private static func write(_ image: CGImage, to url: URL, format: OutputFormat) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw UpscaleError.exportFailed(
                "Не удалось создать каталог: \(error.localizedDescription)"
            )
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.uti,
            1,
            nil
        ) else {
            throw UpscaleError.exportFailed("Не удалось открыть файл «\(url.lastPathComponent)».")
        }

        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw UpscaleError.exportFailed("Не удалось записать «\(url.lastPathComponent)».")
        }
    }

    // MARK: - Async bridge

    private static func runAsync<T>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task.detached {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard let result = box.result else {
            throw UpscaleError.inferenceFailed("Не удалось дождаться обработки.")
        }
        return try result.get()
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    // MARK: - Text

    private enum CLIError: Error {
        case usage(String)

        var message: String {
            switch self {
            case .usage(let message): return message
            }
        }
    }

    private static func writeError(_ message: String) {
        guard let data = ("Error: " + message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    private static let helpText = """
    Waifu2x — native macOS waifu2x frontend

    Usage:
      Waifu2x --upscale <input> --output <output> [options]
      Waifu2x --models
      Waifu2x --help

    Options:
      --style anime|photo        Model style (default: anime)
      --noise none|0|1|2|3       Denoise level (default: 1)
      --scale 2|4                Upscale factor (default: 2)
      --engine waifu2x|fast      Neural engine or Lanczos fallback (default: waifu2x)

    Output format is chosen from the extension: .png or .jpg/.jpeg.
    """
}
