#!/usr/bin/env swift
import AppKit
import Foundation

// Generates Assets/AppIcon.icns from vector drawing code.
// Usage: swift Scripts/make-icon.swift

let fileManager = FileManager.default
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let assetsDirectory = root.appendingPathComponent("Assets")
let distDirectory = root.appendingPathComponent("dist")
try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: distDirectory, withIntermediateDirectories: true)

let canvasSize = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not allocate icon bitmap")
}
bitmap.size = NSSize(width: canvasSize, height: canvasSize)

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create drawing context")
}
NSGraphicsContext.current = context
context.shouldAntialias = true
context.imageInterpolation = .high

drawIcon()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let masterData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
let masterURL = distDirectory.appendingPathComponent("icon-master.png")
try masterData.write(to: masterURL)

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

// Small preview for visual verification.
let preview32URL = distDirectory.appendingPathComponent("icon-32.png")
try run("/usr/bin/sips", ["-z", "32", "32", masterURL.path, "--out", preview32URL.path])

print("Icon written to \(icnsURL.path)")
print("Master preview: \(masterURL.path)")

// MARK: - Drawing

func drawIcon() {
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

    let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = squirclePath(rect: tileRect, exponent: 5.0)

    // Baked icon shadow.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.37, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Base vertical gradient: luminous indigo at the top, deep indigo at the bottom.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()

    let baseColors = [
        NSColor(calibratedRed: 0.45, green: 0.41, blue: 0.88, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.28, green: 0.24, blue: 0.63, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.29, alpha: 1).cgColor,
    ] as CFArray
    let baseLocations: [CGFloat] = [0, 0.52, 1]
    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: baseColors,
        locations: baseLocations
    ) {
        cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: 512, y: 930),
            end: CGPoint(x: 512, y: 96),
            options: []
        )
    }

    // Soft light from the upper left.
    let glowColors = [
        NSColor.white.withAlphaComponent(0.20).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray
    if let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: glowColors,
        locations: [0, 1]
    ) {
        cgContext.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: 330, y: 830),
            startRadius: 0,
            endCenter: CGPoint(x: 360, y: 800),
            endRadius: 600,
            options: []
        )
    }

    // Inner vertical shade at the bottom for depth.
    let floorColors = [
        NSColor.black.withAlphaComponent(0.0).cgColor,
        NSColor.black.withAlphaComponent(0.24).cgColor,
    ] as CFArray
    if let floor = CGGradient(
        colorsSpace: colorSpace,
        colors: floorColors,
        locations: [0, 1]
    ) {
        cgContext.drawLinearGradient(
            floor,
            start: CGPoint(x: 512, y: 420),
            end: CGPoint(x: 512, y: 100),
            options: []
        )
    }
    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim.
    NSGraphicsContext.saveGraphicsState()
    let rim = squirclePath(rect: tileRect.insetBy(dx: 2.5, dy: 2.5), exponent: 5.0)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    rim.lineWidth = 5
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Quiet image frame, hinting at a picture canvas.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let frameRect = NSRect(x: 292, y: 300, width: 440, height: 440)
    let frame = NSBezierPath(
        roundedRect: frameRect,
        xRadius: 98,
        yRadius: 98
    )
    NSColor.white.withAlphaComponent(0.10).setStroke()
    frame.lineWidth = 3
    frame.stroke()

    // Faint corner ticks.
    NSColor.white.withAlphaComponent(0.16).setFill()
    for point in [
        CGPoint(x: 292, y: 740), CGPoint(x: 732, y: 740),
        CGPoint(x: 292, y: 300), CGPoint(x: 732, y: 300),
    ] {
        NSBezierPath(ovalIn: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Warm halo behind the main sparkle.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let haloColors = [
        NSColor(calibratedRed: 0.80, green: 0.78, blue: 1.0, alpha: 0.30).cgColor,
        NSColor(calibratedRed: 0.80, green: 0.78, blue: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    if let halo = CGGradient(
        colorsSpace: colorSpace,
        colors: haloColors,
        locations: [0, 1]
    ) {
        cgContext.drawRadialGradient(
            halo,
            startCenter: CGPoint(x: 492, y: 520),
            startRadius: 20,
            endCenter: CGPoint(x: 492, y: 520),
            endRadius: 360,
            options: []
        )
    }
    NSGraphicsContext.restoreGraphicsState()

    drawSparkle(center: CGPoint(x: 488, y: 512), width: 355, height: 410, alpha: 1.0, glowing: true)
    drawSparkle(center: CGPoint(x: 724, y: 764), width: 152, height: 172, alpha: 0.92, glowing: false)
    drawSparkle(center: CGPoint(x: 300, y: 288), width: 84, height: 96, alpha: 0.56, glowing: false)
    drawSparkle(center: CGPoint(x: 728, y: 336), width: 40, height: 46, alpha: 0.34, glowing: false)
}

func drawSparkle(center: CGPoint, width: CGFloat, height: CGFloat, alpha: CGFloat, glowing: Bool) {
    let path = sparklePath(center: center, width: width, height: height)

    if glowing {
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor(calibratedRed: 0.82, green: 0.80, blue: 1.0, alpha: 0.55)
        glow.shadowBlurRadius = 46
        glow.shadowOffset = .zero
        glow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let start = NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: alpha)
    let end = NSColor(calibratedRed: 0.83, green: 0.80, blue: 1.0, alpha: alpha)
    if let gradient = NSGradient(starting: start, ending: end) {
        gradient.draw(in: path, angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()
}

func sparklePath(center: CGPoint, width: CGFloat, height: CGFloat) -> NSBezierPath {
    let top = CGPoint(x: center.x, y: center.y + height / 2)
    let right = CGPoint(x: center.x + width / 2, y: center.y)
    let bottom = CGPoint(x: center.x, y: center.y - height / 2)
    let left = CGPoint(x: center.x - width / 2, y: center.y)

    let insetX = width * 0.13
    let insetY = height * 0.13

    let controls: [CGPoint] = [
        CGPoint(x: center.x + insetX, y: center.y + insetY),
        CGPoint(x: center.x + insetX, y: center.y - insetY),
        CGPoint(x: center.x - insetX, y: center.y - insetY),
        CGPoint(x: center.x - insetX, y: center.y + insetY),
    ]

    let path = NSBezierPath()
    path.move(to: top)
    path.curve(to: right, controlPoint1: controls[0], controlPoint2: controls[0])
    path.curve(to: bottom, controlPoint1: controls[1], controlPoint2: controls[1])
    path.curve(to: left, controlPoint1: controls[2], controlPoint2: controls[2])
    path.curve(to: top, controlPoint1: controls[3], controlPoint2: controls[3])
    path.close()
    return path
}

func squirclePath(rect: NSRect, exponent: CGFloat) -> NSBezierPath {
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
