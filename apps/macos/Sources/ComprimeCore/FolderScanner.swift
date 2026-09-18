import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct FolderScanner: Sendable {
    public let limits: ScanLimits
    public init(limits: ScanLimits = ScanLimits()) { self.limits = limits }

    /// Work runs on a detached task; stream termination cancels its producer.
    public func scan(_ folder: URL) -> AsyncThrowingStream<ScanSnapshot, Error> {
        // There are at most one initial update plus one every 48 examined entries,
        // so retaining these snapshots keeps the first result observable even when
        // a local disk scan finishes before the main actor gets its first turn.
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let manager = FileManager.default
                    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                                    .fileSizeKey, .contentModificationDateKey]
                    let entries = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys),
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    var snapshot = ScanSnapshot()
                    var thumbnailBytes = 0
                    for url in entries {
                        try Task.checkCancellation()
                        let name = url.lastPathComponent
                        if name == "Comprimidas" || name.hasPrefix("Comprimidas-") || name == ".comprime-backups" {
                            snapshot.excluded += 1
                            continue
                        }
                        do {
                            let values = try url.resourceValues(forKeys: keys)
                            guard values.isSymbolicLink != true, values.isPackage != true, values.isRegularFile == true else {
                                snapshot.excluded += 1
                                continue
                            }
                            snapshot.examined += 1
                            let remainingThumbnailBytes = snapshot.assets.count < limits.eagerThumbnailCount
                                ? max(0, limits.thumbnailBudget - thumbnailBytes)
                                : 0
                            let inspected = try autoreleasepool {
                                try inspect(url, values: values, remainingThumbnailBytes: remainingThumbnailBytes)
                            }
                            thumbnailBytes += inspected.thumbnail?.count ?? 0
                            snapshot.assets.append(inspected)
                        } catch {
                            snapshot.issues.append(ScanIssue(url: url, reason: error.localizedDescription))
                        }
                        // Yield the first usable result immediately. Subsequent larger batches
                        // avoid repeatedly rebuilding a long SwiftUI sidebar during a scan.
                        if snapshot.assets.count == 1 || snapshot.examined % 48 == 0 {
                            continuation.yield(snapshot)
                        }
                    }
                    try Task.checkCancellation()
                    snapshot.isComplete = true
                    continuation.yield(snapshot)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func inspect(_ url: URL, values: URLResourceValues, remainingThumbnailBytes: Int) throws -> ImageAsset {
        let bytes = Int64(values.fileSize ?? 0)
        guard bytes > 0, bytes <= limits.maxSourceBytes else { throw ScanFailure.message("Archivo vacío o mayor al límite de análisis.") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              let format = ImageFormat(typeIdentifier: type) else {
            throw ScanFailure.message("Contenido no compatible o archivo dañado.")
        }
        guard CGImageSourceGetCount(source) == 1 else { throw ScanFailure.message("Secuencias o imágenes animadas no admitidas en esta beta.") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0 else { throw ScanFailure.message("No se pudieron leer las dimensiones.") }
        guard Int64(width) <= limits.maxPixels / Int64(height) else { throw ScanFailure.message("Supera el límite preventivo de píxeles.") }
        // Phase 1 inventory only: unsupported auxiliary/HDR detection is not yet a compression eligibility claim.
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let alpha = properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
        var thumbnail: Data?
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: limits.thumbnailEdge,
                kCGImageSourceShouldCacheImmediately: true
           ] as CFDictionary) else { throw ScanFailure.message("No se pudo decodificar la imagen.") }
        if remainingThumbnailBytes > 0 {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                if CGImageDestinationFinalize(destination), data.length <= remainingThumbnailBytes { thumbnail = data as Data }
            }
        }
        return ImageAsset(url: url, format: format, bytes: bytes, width: width, height: height,
                          orientation: orientation, hasAlphaChannel: alpha,
                          colorProfile: properties[kCGImagePropertyProfileName as String] as? String,
                          modifiedAt: values.contentModificationDate, thumbnail: thumbnail)
    }
}
private enum ScanFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
