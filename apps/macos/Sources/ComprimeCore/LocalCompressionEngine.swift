import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import CWebP
import CryptoKit

public enum EngineFailure: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

extension ImageFormat {
    public var fileExtension: String {
        switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic, .heif: return "heic"; case .webp: return "webp" }
    }
    var identifier: CFString {
        switch self { case .jpeg: return "public.jpeg" as CFString; case .png: return "public.png" as CFString
        case .heic, .heif: return "public.heic" as CFString; case .webp: return "org.webmproject.webp" as CFString }
    }
}

public struct LocalCompressionEngine: CompressionEngine {
    public init() {}
    public func compress(_ asset: ImageAsset, request: CompressionRequest) async throws -> CompressionCandidate {
        try autoreleasepool { try compressSync(asset, request: request) }
    }
    private func compressSync(_ asset: ImageAsset, request: CompressionRequest) throws -> CompressionCandidate {
        try Task.checkCancellation()
        let before = try fingerprint(asset.url)
        guard before.bytes == asset.bytes, asset.modifiedAt == before.date else { throw CompressionError.changedSource }
        let sourceBytes = try Data(contentsOf: asset.url, options: .mappedIfSafe)
        let sourceHash = SHA256.hash(data: sourceBytes)
        guard let source = CGImageSourceCreateWithData(sourceBytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw EngineFailure.message("La imagen está dañada o contiene múltiples fotogramas.")
        }
        guard (raw[kCGImagePropertyDepth as String] as? Int ?? 8) <= 8 else {
            throw EngineFailure.message("Las imágenes HDR o de más de 8 bits aún no se transforman para evitar perder información.")
        }
        for auxiliary in [kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity, kCGImageAuxiliaryDataTypeHDRGainMap] {
            if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliary) != nil {
                throw EngineFailure.message("Esta imagen contiene HDR, profundidad o datos auxiliares que la beta no puede conservar.")
            }
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Comprime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        var returned = false
        defer { if !returned { try? FileManager.default.removeItem(at: temp) } }
        func unchanged(_ warnings: [String] = []) throws -> CompressionCandidate {
            let url = temp.appendingPathComponent("result.\(asset.url.pathExtension)")
            try sourceBytes.write(to: url, options: .withoutOverwriting)
            let swap = (5...8).contains(asset.orientation)
            return CompressionCandidate(temporaryURL: url, bytes: asset.bytes,
                width: swap ? asset.height : asset.width, height: swap ? asset.width : asset.height,
                format: asset.format, quality: nil, warnings: warnings)
        }
        let mustConvert: Bool
        if case .convert = request.outputMode { mustConvert = true } else { mustConvert = false }
        let mayReuse = !mustConvert && request.metadataPolicy == .preserve && !request.removeGPS
        if mayReuse && asset.bytes <= request.targetBytes {
            let value = try unchanged()
            try verifyUnchanged(asset.url, hash: sourceHash)
            returned = true
            return value
        }
        guard let original = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(asset.width, asset.height),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw CompressionError.encodeFailed }
        let transparent = asset.hasAlphaChannel ? try hasTransparency(original) : false
        var formats: [ImageFormat]
        switch request.outputMode {
        case .preserve: formats = [asset.format]
        case .convert(let format): formats = [format]
        case .automatic:
            formats = [asset.format]
            let alternative: ImageFormat = transparent ? .webp : (asset.format == .png ? .jpeg : .webp)
            if !formats.contains(alternative) { formats.append(alternative) }
        }
        if transparent {
            formats = formats.filter { $0 == .png || $0 == .webp }
            guard !formats.isEmpty else { throw EngineFailure.message("Esta imagen tiene transparencia. Elige PNG o WebP para conservarla.") }
        }
        let scales: [Double] = request.allowResize ? [1, 0.9, 0.8, 0.7, 0.6, 0.5] : [1]
        var best: (data: Data, image: CGImage, format: ImageFormat, quality: Double?)?
        var chosen: (data: Data, image: CGImage, format: ImageFormat, quality: Double?)?
        let minEdge = min(max(original.width, original.height), 1280)
        var warnings: [String] = []
        if request.metadataPolicy == .preserve {
            warnings.append("Se conserva metadata EXIF/IPTC compatible. Campos XMP o propietarios no representables pueden omitirse.")
        }
        if request.removeGPS { warnings.append("Ubicación, notas del fabricante y campos descriptivos de ubicación retirados.") }
        outer: for scale in scales {
            if Int(Double(max(original.width, original.height)) * scale) < minEdge { break }
            try Task.checkCancellation()
            let resized = try resize(original, scale: scale)
            for format in formats {
                let props = properties(raw, request: request, image: resized)
                var winner: (Data, Double?)?
                func trial(_ quality: Double?) throws -> Data {
                    try Task.checkCancellation()
                    let data = try encode(resized, format: format, quality: quality, properties: props)
                    if best == nil || data.count < best!.data.count { best = (data, resized, format, quality) }
                    return data
                }
                if format == .png {
                    let data = try trial(nil)
                    if data.count <= request.targetBytes { winner = (data, nil) }
                } else {
                    let maximum = try trial(1)
                    if maximum.count <= request.targetBytes { winner = (maximum, 1) }
                    else {
                        let minimum = try trial(0.70)
                        if minimum.count <= request.targetBytes {
                            winner = (minimum, 0.70)
                            var low = 70, high = 99
                            while low <= high {
                                let midpoint = (low + high) / 2
                                let q = Double(midpoint) / 100
                                let data = try trial(q)
                                if data.count <= request.targetBytes { winner = (data, q); low = midpoint + 1 }
                                else { high = midpoint - 1 }
                            }
                        }
                    }
                }
                if let winner { chosen = (winner.0, resized, format, winner.1); break outer }
            }
        }
        guard let result = chosen ?? best else { throw CompressionError.encodeFailed }
        if chosen == nil { warnings.append("No se pudo alcanzar el objetivo respetando los límites de calidad y resolución.") }
        if mayReuse && result.data.count >= asset.bytes {
            let value = try unchanged(warnings + ["Sin reducción útil: se conserva el archivo original."])
            try verifyUnchanged(asset.url, hash: sourceHash)
            returned = true
            return value
        }
        if result.image.width != original.width || result.image.height != original.height {
            warnings.append("Resolución reducida: \(original.width) × \(original.height) → \(result.image.width) × \(result.image.height).")
        }
        let targetURL = temp.appendingPathComponent("result.\(result.format.fileExtension)")
        try result.data.write(to: targetURL, options: .withoutOverwriting)
        guard let check = CGImageSourceCreateWithURL(targetURL as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(check, 0, nil),
              decoded.width == result.image.width, decoded.height == result.image.height else { throw CompressionError.encodeFailed }
        try verifyUnchanged(asset.url, hash: sourceHash)
        try Task.checkCancellation()
        returned = true
        return CompressionCandidate(temporaryURL: targetURL, bytes: Int64(result.data.count), width: decoded.width,
            height: decoded.height, format: result.format == .heif ? .heic : result.format, quality: result.quality, warnings: warnings)
    }

    private func hasTransparency(_ image: CGImage) throws -> Bool {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            let raw = ctx.data else { throw CompressionError.insufficientMemory }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = raw.assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: image.width * image.height * 4, by: 4).contains { pixels[$0] < 255 }
    }

    private func resize(_ image: CGImage, scale: Double) throws -> CGImage {
        if scale == 1 { return image }
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CompressionError.insufficientMemory }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else { throw CompressionError.encodeFailed }
        return result
    }

    private func properties(_ raw: [String: Any], request: CompressionRequest, image: CGImage) -> [String: Any] {
        var result: [String: Any] = [:]
        if request.metadataPolicy == .preserve {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary] {
                if let value = raw[key as String] { result[key as String] = value }
            }
        }
        if request.removeGPS {
            result.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
            result.removeValue(forKey: kCGImagePropertyIPTCDictionary as String)
            if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                exif.removeValue(forKey: kCGImagePropertyExifMakerNote as String)
                exif.removeValue(forKey: kCGImagePropertyExifUserComment as String)
                result[kCGImagePropertyExifDictionary as String] = exif
            }
            if var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff.removeValue(forKey: kCGImagePropertyTIFFImageDescription as String)
                result[kCGImagePropertyTIFFDictionary as String] = tiff
            }
        }
        result[kCGImagePropertyOrientation as String] = 1
        var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        result[kCGImagePropertyTIFFDictionary as String] = tiff
        var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension as String] = image.width
        exif[kCGImagePropertyExifPixelYDimension as String] = image.height
        result[kCGImagePropertyExifDictionary as String] = exif
        return result
    }

    private func encode(_ image: CGImage, format: ImageFormat, quality: Double?, properties: [String: Any]) throws -> Data {
        if format == .webp { return try encodeWebP(image, quality: quality ?? 1, properties: properties) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.identifier, 1, nil) else {
            throw EngineFailure.message("El sistema no tiene un encoder disponible para \(format.rawValue).")
        }
        var props = properties
        if let quality { props[kCGImageDestinationLossyCompressionQuality as String] = quality }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CompressionError.encodeFailed }
        return data as Data
    }

    private func encodeWebP(_ image: CGImage, quality: Double, properties: [String: Any]) throws -> Data {
        let width = image.width, height = image.height
        guard width <= 16383, height <= 16383 else { throw EngineFailure.message("WebP admite como máximo 16.383 píxeles por lado.") }
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            let pixels = ctx.data else { throw CompressionError.insufficientMemory }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rgba = pixels.assumingMemoryBound(to: UInt8.self)
        // libwebp expects straight alpha, whereas Core Graphics renders premultiplied RGBA.
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = Int(rgba[offset + 3])
            if alpha > 0 && alpha < 255 {
                for channel in 0..<3 { rgba[offset + channel] = UInt8(min(255, (Int(rgba[offset + channel]) * 255 + alpha / 2) / alpha)) }
            }
        }
        var output: UnsafeMutablePointer<UInt8>?
        let count = WebPEncodeRGBA(rgba, Int32(width), Int32(height), Int32(width * 4), Float(quality * 100), &output)
        guard count > 0, let output else { throw CompressionError.encodeFailed }
        defer { WebPFree(output) }
        var webp = WebPData(bytes: UnsafePointer(output), size: count)
        guard let mux = WebPMuxCreate(&webp, 1) else { throw CompressionError.encodeFailed }
        defer { WebPMuxDelete(mux) }
        func chunk(_ name: String, _ data: Data) throws {
            let status = data.withUnsafeBytes { raw -> WebPMuxError in
                var chunkData = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
                return WebPMuxSetChunk(mux, name, &chunkData, 1)
            }
            guard status == WEBP_MUX_OK else { throw CompressionError.encodeFailed }
        }
        if let icc = space.copyICCData() as Data? { try chunk("ICCP", icc) }
        // ImageIO serializes supported EXIF fields to a standards-compliant TIFF block.
        let tinySpace = CGColorSpace(name: CGColorSpace.sRGB)!
        if let small = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: tinySpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage() {
            let carrier = try encode(small, format: .jpeg, quality: 0.7, properties: properties)
            if let exif = extractEXIF(carrier) { try chunk("EXIF", exif) }
        }
        var assembled = WebPData(bytes: nil, size: 0)
        guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK, let bytes = assembled.bytes else { throw CompressionError.encodeFailed }
        defer { WebPDataClear(&assembled) }
        return Data(bytes: bytes, count: assembled.size)
    }
    private func extractEXIF(_ jpeg: Data) -> Data? {
        let a = [UInt8](jpeg)
        var i = 2
        while i + 4 <= a.count {
            guard a[i] == 0xff else { break }
            let marker = a[i+1]
            if marker == 0xda || marker == 0xd9 { break }
            let length = Int(a[i+2]) * 256 + Int(a[i+3])
            guard length >= 2, i + 2 + length <= a.count else { break }
            if marker == 0xe1, length >= 8, Array(a[(i+4)..<(i+10)]) == [69,120,105,102,0,0] {
                return Data(a[(i+10)..<(i+2+length)])
            }
            i += 2 + length
        }
        return nil
    }
}

public func discard(_ candidate: CompressionCandidate) {
    let parent = candidate.temporaryURL.deletingLastPathComponent()
    if parent.lastPathComponent.hasPrefix("Comprime-") { try? FileManager.default.removeItem(at: parent) }
}
func fingerprint(_ url: URL) throws -> (bytes: Int64, date: Date?) {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isRegularFileKey])
    guard values.isSymbolicLink != true, values.isRegularFile == true else { throw CompressionError.changedSource }
    return (Int64(values.fileSize ?? 0), values.contentModificationDate)
}
func verifyUnchanged(_ url: URL, hash: SHA256.Digest) throws {
    _ = try fingerprint(url)
    guard SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)) == hash else { throw CompressionError.changedSource }
}
