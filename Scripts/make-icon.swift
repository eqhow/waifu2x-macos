#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Builds the Waifu2x app icon from Assets/AppIconSource.jpg.
//
// The portrait is treated as an ink print: white paper becomes transparent,
// dark lines become warm black ink, and the result is composed on a warm
// paper tile with a thin frame and a small indigo seal.
//
// Usage: swift Scripts/make-icon.swift [source.jpg]

let fileManager = FileManager.default
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetsDirectory = root.appendingPathComponent("Assets")
let distDirectory = root.appendingPathComponent("dist")
let docsDirectory = root.appendingPathComponent("docs")

try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: distDirectory, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: docsDirectory, withIntermediateDirectories: true)

let defaultSource = assetsDirectory.appendingPathComponent("AppIconSource.jpg")
let sourceURL: URL
if CommandLine.arguments.count > 1 {
    sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    sourceURL = defaultSource
}

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let sourceCG = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not read source image at \(sourceURL.path)")
}

let canvasSize = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not allocate icon bitmap")
}

context.setShouldAntialias(true)
context.interpolationQuality = .high

let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext

let inkImage = makeInkImage(from: sourceCG)
drawIcon(in: context, ink: inkImage)

nsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let masterImage = context.makeImage() else {
    fatalError("Could not create master icon image")
}
let masterURL = distDirectory.appendingPathComponent("icon-master.png")
try writePNG(masterImage, to: masterURL)

// Build the .iconset with sips.
let iconsetURL = fileManager.temporaryDirectory.appendingPathComponent("Waifu2x.iconset")
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in variants {
    let output = iconsetURL.appendingPathComponent(name)
    try run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", masterURL.path, "--out", output.path])
}

let icnsURL = assetsDirectory.appendingPathComponent("AppIcon.icns")
try? fileManager.removeItem(at: icnsURL)
try run("/usr/bin/iconutil", ["-c", "icns", iconsetURL.path, "-o", icnsURL.path])

// Previews for visual checks and for the README.
let previews: [(String, Int)] = [
    ("icon-16.png", 16),
    ("icon-32.png", 32),
    ("icon-128.png", 128),
]
for (name, pixels) in previews {
    let output = distDirectory.appendingPathComponent(name)
    try run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", masterURL.path, "--out", output.path])
}

let docsIconURL = docsDirectory.appendingPathComponent("icon.png")
try run("/usr/bin/sips", ["-z", "256", "256", masterURL.path, "--out", docsIconURL.path])

print("Icon written to \(icnsURL.path)")
print("Master preview: \(masterURL.path)")
print("README icon: \(docsIconURL.path)")

// MARK: - Drawing

func drawIcon(in context: CGContext, ink: CGImage) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    context.clear(canvas)

    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = squirclePath(rect: tileRect, exponent: 5.0)

    let paperTop = NSColor(srgbRed: 0.973, green: 0.953, blue: 0.910, alpha: 1)
    let paperMid = NSColor(srgbRed: 0.949, green: 0.922, blue: 0.865, alpha: 1)
    let paperBottom = NSColor(srgbRed: 0.914, green: 0.878, blue: 0.808, alpha: 1)
    let inkColor = NSColor(srgbRed: 0.086, green: 0.082, blue: 0.118, alpha: 1)
    let indigo = NSColor(srgbRed: 0.165, green: 0.157, blue: 0.345, alpha: 1)

    // Baked contact shadow: a broad ambient pass plus a tighter near pass.
    NSGraphicsContext.saveGraphicsState()
    let ambient = NSShadow()
    ambient.shadowColor = NSColor(srgbRed: 0.055, green: 0.047, blue: 0.094, alpha: 0.30)
    ambient.shadowBlurRadius = 42
    ambient.shadowOffset = NSSize(width: 0, height: -20)
    ambient.set()
    paperBottom.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let contact = NSShadow()
    contact.shadowColor = NSColor(srgbRed: 0.055, green: 0.047, blue: 0.094, alpha: 0.20)
    contact.shadowBlurRadius = 12
    contact.shadowOffset = NSSize(width: 0, height: -5)
    contact.set()
    paperBottom.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Paper field.
    context.saveGState()
    tilePath.addClip()

    let baseColors = [paperTop.cgColor, paperMid.cgColor, paperBottom.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: baseColors, locations: [0, 0.55, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 512, y: 924),
            end: CGPoint(x: 512, y: 100),
            options: []
        )
    }

    let highlightColors = [
        NSColor(srgbRed: 1, green: 0.99, blue: 0.96, alpha: 0.32).cgColor,
        NSColor(srgbRed: 1, green: 0.99, blue: 0.96, alpha: 0).cgColor,
    ] as CFArray
    if let highlight = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0, 1]) {
        context.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: 330, y: 840),
            startRadius: 0,
            endCenter: CGPoint(x: 360, y: 810),
            endRadius: 640,
            options: []
        )
    }

    let floorColors = [
        NSColor(srgbRed: 0.28, green: 0.23, blue: 0.15, alpha: 0).cgColor,
        NSColor(srgbRed: 0.28, green: 0.23, blue: 0.15, alpha: 0.075).cgColor,
    ] as CFArray
    if let floor = CGGradient(colorsSpace: colorSpace, colors: floorColors, locations: [0, 1]) {
        context.drawLinearGradient(
            floor,
            start: CGPoint(x: 512, y: 430),
            end: CGPoint(x: 512, y: 100),
            options: []
        )
    }

    drawPaperGrain(in: context, tileRect: tileRect, ink: inkColor)

    context.restoreGState()

    // The portrait keeps its original square composition, clipped to a
    // rounded panel. Its white paper becomes the tile paper, so only the
    // ink drawing remains visible.
    let portraitRect = tileRect.insetBy(dx: 40, dy: 40)
    let portraitPanel = squirclePath(rect: portraitRect, exponent: 5.0)

    context.saveGState()
    portraitPanel.addClip()
    context.interpolationQuality = .high
    context.draw(ink, in: portraitRect)
    context.restoreGState()

    // A thin ink frame on the paper matte turns the source's square crop
    // into an intentional page edge instead of a pasted-in image boundary.
    let frameRect = tileRect.insetBy(dx: 22, dy: 22)
    let frame = squirclePath(rect: frameRect, exponent: 5.0)
    inkColor.withAlphaComponent(0.50).setStroke()
    frame.lineWidth = 3
    frame.stroke()

    // A small indigo seal in the open paper at the lower right.
    drawSeal(
        in: context,
        center: CGPoint(x: 824, y: 200),
        size: 64,
        indigo: indigo,
        paper: paperTop
    )
}

func drawPaperGrain(in context: CGContext, tileRect: CGRect, ink: NSColor) {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) & 0xFFFFF) / CGFloat(0xFFFFF)
    }

    let darkPath = CGMutablePath()
    let lightPath = CGMutablePath()

    for _ in 0..<6200 {
        let x = tileRect.minX + next() * tileRect.width
        let y = tileRect.minY + next() * tileRect.height
        let radius = 0.45 + next() * 0.85
        darkPath.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
    for _ in 0..<2600 {
        let x = tileRect.minX + next() * tileRect.width
        let y = tileRect.minY + next() * tileRect.height
        let radius = 0.4 + next() * 0.7
        lightPath.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    context.saveGState()
    context.addPath(darkPath)
    context.setFillColor(ink.withAlphaComponent(0.045).cgColor)
    context.fillPath()

    context.addPath(lightPath)
    context.setFillColor(NSColor(srgbRed: 1, green: 0.995, blue: 0.97, alpha: 0.10).cgColor)
    context.fillPath()
    context.restoreGState()
}

func drawSeal(
    in context: CGContext,
    center: CGPoint,
    size: CGFloat,
    indigo: NSColor,
    paper: NSColor
) {
    let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)

    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: -6 * .pi / 180)
    context.translateBy(x: -center.x, y: -center.y)

    let sealPath = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
    indigo.setFill()
    sealPath.fill()

    // A hairline of paper inside the seal makes it read as a stamp.
    let inset = rect.insetBy(dx: 4, dy: 4)
    let inner = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
    paper.withAlphaComponent(0.55).setStroke()
    inner.lineWidth = 1
    inner.stroke()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 25, weight: .semibold),
        .foregroundColor: paper,
        .kern: -0.4,
    ]
    let text = NSAttributedString(string: "2×", attributes: attributes)
    let textSize = text.size()
    text.draw(at: CGPoint(
        x: center.x - textSize.width / 2,
        y: center.y - textSize.height / 2 + 1
    ))

    context.restoreGState()
}

// MARK: - Source processing

func makeInkImage(from image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let sourceContext = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not decode source image")
    }
    sourceContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Deep indigo-black ink; the paper shows through wherever the source is white.
    let inkR = 0.086
    let inkG = 0.082
    let inkB = 0.118

    var output = [UInt8](repeating: 0, count: height * bytesPerRow)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[index]) / 255
        let g = Double(pixels[index + 1]) / 255
        let b = Double(pixels[index + 2]) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        let whitePoint = 0.965
        let blackPoint = 0.045
        var alpha = (whitePoint - luminance) / (whitePoint - blackPoint)
        alpha = min(max(alpha, 0), 1)
        alpha = pow(alpha, 0.92)

        output[index] = UInt8((inkR * alpha * 255).rounded())
        output[index + 1] = UInt8((inkG * alpha * 255).rounded())
        output[index + 2] = UInt8((inkB * alpha * 255).rounded())
        output[index + 3] = UInt8((alpha * 255).rounded())
    }

    guard let provider = CGDataProvider(data: Data(output) as CFData),
          let inkImage = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: bytesPerRow,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: true,
              intent: .defaultIntent
          ) else {
        fatalError("Could not create ink image")
    }
    return inkImage
}

// MARK: - Helpers

func squirclePath(rect: CGRect, exponent: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let cx = rect.midX
    let cy = rect.midY
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 720
    let power = 2 / exponent

    for index in 0...steps {
        let angle = CGFloat(index) / CGFloat(steps) * .pi * 2
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = cx + a * copysign(pow(abs(cosine), power), cosine)
        let y = cy + b * copysign(pow(abs(sine), power), sine)
        if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.line(to: CGPoint(x: x, y: y))
        }
    }
    path.close()
    return path
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not create PNG destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write PNG")
    }
}

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("\(tool) failed with status \(process.terminationStatus)")
    }
}
