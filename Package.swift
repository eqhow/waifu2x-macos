// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Waifu2x",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Waifu2x", targets: ["Waifu2x"])
    ],
    targets: [
        .executableTarget(
            name: "Waifu2x",
            path: "Sources/Waifu2x",
            resources: [
                .copy("Resources/Models")
            ]
        )
    ]
)
