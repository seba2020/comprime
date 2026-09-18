// swift-tools-version: 5.9
import PackageDescription
import Foundation
let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor/lib").path

let package = Package(
    name: "Comprime",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ComprimeCore", targets: ["ComprimeCore"]), .executable(name: "Comprime", targets: ["Comprime"]), .executable(name: "CodecProbe", targets: ["CodecProbe"]), .executable(name: "SmokeChecks", targets: ["SmokeChecks"]), .executable(name: "EngineChecks", targets: ["EngineChecks"])],
    targets: [
        .target(name: "CWebP", linkerSettings: [.unsafeFlags(["-L", vendor]), .linkedLibrary("webpmux"), .linkedLibrary("webp"), .linkedLibrary("sharpyuv")]),
        .target(name: "ComprimeCore", dependencies: ["CWebP"]),
        .executableTarget(name: "Comprime", dependencies: ["ComprimeCore"]),
        .executableTarget(name: "CodecProbe", dependencies: ["ComprimeCore"]),
        .executableTarget(name: "SmokeChecks", dependencies: ["ComprimeCore"]),
        .executableTarget(name: "EngineChecks", dependencies: ["ComprimeCore"]),
        .testTarget(name: "ComprimeCoreTests", dependencies: ["ComprimeCore"])
    ]
)
