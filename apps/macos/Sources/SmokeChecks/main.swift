import Foundation
import ImageIO
import CoreGraphics
import ComprimeCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "SmokeChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    print("PASS: \(message)")
}
func scan(_ url: URL, limits: ScanLimits = ScanLimits()) async throws -> ScanSnapshot {
    var final = ScanSnapshot()
    for try await update in FolderScanner(limits: limits).scan(url) { final = update }
    return final
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("comprime-check-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let ctx = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 0.4, alpha: 0.5))
ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
let imageURL = root.appendingPathComponent("alpha.not-png")
let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
try expect(CGImageDestinationFinalize(destination), "Generate synthetic alpha PNG")
let original = try Data(contentsOf: imageURL)
try original.write(to: root.appendingPathComponent(".hidden.png"))
try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: imageURL)
let nested = root.appendingPathComponent("subfolder")
try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
try original.write(to: nested.appendingPathComponent("nested.png"))
try Data("invalid image".utf8).write(to: root.appendingPathComponent("broken.jpg"))
let result = try await scan(root)
try expect(result.isComplete && result.assets.count == 1, "Detect content independently of extension")
try expect(result.assets[0].hasAlphaChannel && result.assets[0].width == 32 && result.assets[0].height == 24, "Read alpha and dimensions")
try expect(result.excluded == 2 && result.issues.count == 1, "Exclude links/subfolders/hidden files and isolate corrupt input")
let after = try Data(contentsOf: imageURL)
try expect(original == after, "Original bytes remain intact")
let limited = try await scan(root, limits: ScanLimits(maxPixels: 100))
try expect(limited.assets.isEmpty, "Pixel budget rejects large inputs before thumbnail decoding")
let noThumb = try await scan(root, limits: ScanLimits(thumbnailBudget: 0))
try expect(noThumb.assets.count == 1 && noThumb.assets[0].thumbnail == nil, "Thumbnail budget does not remove valid inventory")
let empty = root.appendingPathComponent("empty")
try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
let emptyResult = try await scan(empty)
try expect(emptyResult.isComplete && emptyResult.assets.isEmpty, "Empty folder completes cleanly")
do { _ = try CompressionRequest(targetBytes: 0); throw NSError(domain: "Expected rejection", code: 1) }
catch CompressionError.invalidTarget { print("PASS: Reject invalid target") }
do {
    _ = try await scan(root.appendingPathComponent("missing"))
    throw NSError(domain: "Expected directory failure", code: 1)
} catch let error as NSError {
    try expect(error.domain != "Expected directory failure", "Missing folder reports error")
}
if let fixtures = CommandLine.arguments.dropFirst().first {
    let mixed = try await scan(URL(fileURLWithPath: fixtures))
    let formats = Set(mixed.assets.map(\.format))
    try expect(formats.contains(.jpeg) && formats.contains(.png) && formats.contains(.heic) && formats.contains(.webp), "Scan real mixed JPEG/PNG/HEIC/WebP fixtures")
    print("Mixed inventory: \(mixed.assets.count) assets, \(mixed.issues.count) non-image/unsupported entries")
}
print("All executable checks passed.")
