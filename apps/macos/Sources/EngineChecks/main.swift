import Foundation
import ImageIO
import CoreGraphics
import CryptoKit
import ComprimeCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw EngineFailure.message("FAIL: " + message) }
    print("PASS: " + message)
}
func scan(_ folder: URL) async throws -> [ImageAsset] {
    var assets: [ImageAsset] = []
    for try await snapshot in FolderScanner().scan(folder) { assets = snapshot.assets }
    return assets
}
func writeImage(_ image: CGImage, to url: URL, type: String, props: [String: Any] = [:]) throws {
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { throw CompressionError.encodeFailed }
    CGImageDestinationAddImage(dst, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dst) else { throw CompressionError.encodeFailed }
}
func properties(_ url: URL) throws -> [String: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { throw CompressionError.encodeFailed }
    return props
}
func hash(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.temporaryDirectory.appendingPathComponent("Comprime-MVP-\(UUID().uuidString)").path)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let folder = root.appendingPathComponent("inputs-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let width = 1600, height = 1200
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
let rgba = context.data!.assumingMemoryBound(to: UInt8.self)
var seed: UInt32 = 777
for y in 0..<height { for x in 0..<width {
    seed = 1664525 &* seed &+ 1013904223
    let i = (y * width + x) * 4
    let noise = Int((seed >> 24) & 63)
    rgba[i] = UInt8(min(255, x * 170 / width + noise))
    rgba[i+1] = UInt8(min(255, y * 170 / height + noise))
    rgba[i+2] = UInt8(70 + noise)
    rgba[i+3] = 255
} }
let image = context.makeImage()!
let jpeg = folder.appendingPathComponent("photo.jpg")
let meta: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 1.0,
    kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 1.0, kCGImagePropertyGPSLatitudeRef as String: "N"],
    kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFArtist as String: "Synthetic fixture"]]
try writeImage(image, to: jpeg, type: "public.jpeg", props: meta)
try writeImage(image, to: folder.appendingPathComponent("photo.png"), type: "public.png")
try writeImage(image, to: folder.appendingPathComponent("photo.heic"), type: "public.heic", props: [kCGImageDestinationLossyCompressionQuality as String: 0.85])
try writeImage(image, to: folder.appendingPathComponent("rotated.jpg"), type: "public.jpeg", props: [kCGImagePropertyOrientation as String: 6])
context.clear(CGRect(x: 0, y: 0, width: 300, height: 400))
try writeImage(context.makeImage()!, to: folder.appendingPathComponent("transparent.png"), type: "public.png")
let originals = try await scan(folder)
let hashes = try Dictionary(uniqueKeysWithValues: originals.map { ($0.url, try hash($0.url)) })
guard let photo = originals.first(where: { $0.url.lastPathComponent == "photo.jpg" }) else {
    throw EngineFailure.message("Scanner did not return photo.jpg. Found: \(originals.map { $0.url.lastPathComponent })")
}
guard let transparent = originals.first(where: { $0.url.lastPathComponent == "transparent.png" }) else {
    throw EngineFailure.message("Scanner did not return transparent.png. Found: \(originals.map { $0.url.lastPathComponent })")
}
let engine = LocalCompressionEngine()
let target: Int64 = 600_000
let compressed = try await engine.compress(photo, request: try CompressionRequest(targetBytes: target))
print("JPEG diagnostic: original=\(photo.bytes) result=\(compressed.bytes) quality=\(String(describing: compressed.quality)) size=\(compressed.width)x\(compressed.height) warnings=\(compressed.warnings)")
try check(compressed.bytes <= target && compressed.bytes < photo.bytes, "JPEG target search reaches 600 KB with measured bytes")
try check(compressed.quality != nil && compressed.quality! >= 0.70, "Quality floor respected")
let realBytes = try Data(contentsOf: compressed.temporaryURL).count
try check(Int64(realBytes) == compressed.bytes, "Result includes actual encoded metadata bytes")
discard(compressed)
let impossible = try await engine.compress(photo, request: try CompressionRequest(targetBytes: 1, allowResize: false))
try check(impossible.bytes > 1 && !impossible.warnings.isEmpty, "Impossible target returns explicit warning without unbounded degradation")
discard(impossible)
let copy = try await engine.compress(photo, request: try CompressionRequest(targetBytes: 100_000_000))
let copiedHash = try hash(copy.temporaryURL)
try check(copiedHash == hashes[photo.url], "Already-small input copied exactly")
discard(copy)
for format in [ImageFormat.jpeg, .png, .heic, .webp] {
    let result = try await engine.compress(photo, request: try CompressionRequest(targetBytes: 10_000_000, outputMode: .convert(format), removeGPS: true))
    let props = try properties(result.temporaryURL)
    try check(result.format == format && result.width == width && result.height == height, "Convert to \(format.rawValue) and preserve dimensions")
    try check(props[kCGImagePropertyGPSDictionary as String] == nil, "GPS removed from \(format.rawValue)")
    if format == .webp { try FileManager.default.copyItem(at: result.temporaryURL, to: folder.appendingPathComponent("photo.webp")) }
    discard(result)
}
let wp = try await engine.compress(transparent, request: try CompressionRequest(targetBytes: 10_000_000, outputMode: .convert(.webp)))
let wpProps = try properties(wp.temporaryURL)
try check(wpProps[kCGImagePropertyHasAlpha as String] as? Bool == true, "PNG → WebP preserves transparency")
discard(wp)
do {
    let bad = try await engine.compress(transparent, request: try CompressionRequest(targetBytes: 1_000_000, outputMode: .convert(.jpeg)))
    discard(bad); throw EngineFailure.message("Expected transparency rejection")
} catch let error as EngineFailure {
    try check(error.localizedDescription.contains("transparencia"), "Transparent PNG → JPEG rejected")
}
let rotated = originals.first { $0.url.lastPathComponent == "rotated.jpg" }!
let orient = try await engine.compress(rotated, request: try CompressionRequest(targetBytes: 10_000_000, outputMode: .convert(.jpeg)))
try check(orient.width == height && orient.height == width, "EXIF orientation applied exactly once")
discard(orient)
let all = try await scan(folder)
var batch = BatchSnapshot()
for try await state in BatchProcessor().run(folder: folder, assets: all, request: try CompressionRequest(targetBytes: 500_000)) { batch = state }
try check(batch.finished && batch.items.count == all.count, "Mixed batch resolves every input")
try check(batch.items.allSatisfy { $0.output != nil }, "Mixed JPG/PNG/HEIC/WebP batch writes valid outputs")
for asset in originals { let current = try hash(asset.url); try check(current == hashes[asset.url], "Original intact: \(asset.url.lastPathComponent)") }
let secondAssets = all.filter { $0.url.lastPathComponent == "photo.jpg" || $0.url.lastPathComponent == "photo.png" }
var collision = BatchSnapshot()
for try await state in BatchProcessor().run(folder: folder, assets: secondAssets, request: try CompressionRequest(targetBytes: 10_000_000, outputMode: .convert(.webp))) { collision = state }
try check(Set(collision.items.compactMap(\.output)).count == 2, "Converging filenames produce two distinct outputs")
try check(collision.outputFolder != batch.outputFolder, "Repeated runs reserve a new output folder")
let control = BatchControl(); control.cancel()
var cancelled = BatchSnapshot()
for try await state in BatchProcessor().run(folder: folder, assets: all, request: try CompressionRequest(targetBytes: target), control: control) { cancelled = state }
try check(cancelled.cancelled && cancelled.items.allSatisfy { $0.output == nil }, "Cancellation publishes no pending output")
let replaceFolder = root.appendingPathComponent("replace-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: replaceFolder, withIntermediateDirectories: true)
let replaceFile = replaceFolder.appendingPathComponent("photo.jpg")
try FileManager.default.copyItem(at: jpeg, to: replaceFile)
let replaceHash = try hash(replaceFile)
var replaced = BatchSnapshot()
for try await state in BatchProcessor().run(folder: replaceFolder, assets: try await scan(replaceFolder), request: try CompressionRequest(targetBytes: target), replaceOriginals: true) { replaced = state }
try check(replaced.items.first?.output != nil, "Advanced replacement completes")
let backupHash = try hash(replaced.backupFolder!.appendingPathComponent("photo.jpg"))
try check(backupHash == replaceHash, "Independent backup matches exact original bytes")
let replacementHash = try hash(replaceFile)
try check(replacementHash != replaceHash, "Replacement writes compressed content")
print("ALL MVP CHECKS PASSED. Fixtures: \(folder.path)")
