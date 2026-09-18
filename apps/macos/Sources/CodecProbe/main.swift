import Foundation
import ImageIO
import CoreGraphics
import ComprimeCore

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "codec-fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let readTypes = CGImageSourceCopyTypeIdentifiers() as! [String]
let writeTypes = CGImageDestinationCopyTypeIdentifiers() as! [String]
let width = 640, height = 480
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 0.05, green: 0.46, blue: 0.43, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
for x in stride(from: 0, to: width, by: 8) {
    context.setFillColor(CGColor(red: CGFloat(x)/640, green: 0.3, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: x, y: 0, width: 4, height: height))
}
let image = context.makeImage()!
var rows: [[String: Any]] = []
for (type, ext) in [("public.jpeg", "jpg"), ("public.png", "png"), ("public.heic", "heic"), ("public.heif", "heif"), ("org.webmproject.webp", "webp")] {
    var row: [String: Any] = ["type": type, "advertisedRead": readTypes.contains(type), "advertisedWrite": writeTypes.contains(type)]
    var attempts: [[String: Any]] = []
    if writeTypes.contains(type) {
        for quality in [0.70, 0.95] {
            let url = output.appendingPathComponent("synthetic-\(Int(quality*100)).\(ext)")
            var result: [String: Any] = ["qualityRequested": quality]
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                let encoded = CGImageDestinationFinalize(destination)
                result["encoded"] = encoded
                if encoded {
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil)
                    result["decoded"] = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil
                    result["bytes"] = try Data(contentsOf: url).count
                    result["detectedType"] = source.flatMap { CGImageSourceGetType($0) as String? } ?? "unknown"
                }
            } else { result["encoded"] = false }
            attempts.append(result)
        }
    }
    row["attempts"] = attempts
    rows.append(row)
}
let report: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                            "architecture": "arm64", "scope": "Synthetic static RGB image; not metadata, HDR or minimum OS certification", "formats": rows]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("native-codecs.json"))
print(String(decoding: data, as: UTF8.self))
