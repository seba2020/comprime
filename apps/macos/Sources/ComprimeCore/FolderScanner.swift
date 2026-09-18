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
                    let workerCount = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
                    var nextIndex = 0

                    func apply(_ result: EntryResult) {
                        switch result {
                        case .excluded:
                            snapshot.excluded += 1
                        case .asset(let asset):
                            snapshot.examined += 1
                            snapshot.assets.append(asset)
                        case .issue(let issue):
                            snapshot.examined += 1
                            snapshot.issues.append(issue)
                        }
                    }

                    // Inspect the first entry alone so an initial asset can reach the UI
                    // immediately. The remaining entries are processed in bounded parallel
                    // batches that use available CPU and SSD throughput without flooding memory.
                    if let first = entries.first {
                        try Task.checkCancellation()
                        apply(inspectEntry(first, keys: keys, entryIndex: 0))
                        nextIndex = 1
                        if !snapshot.assets.isEmpty || snapshot.examined > 0 { continuation.yield(snapshot) }
                    }

                    while nextIndex < entries.count {
                        try Task.checkCancellation()
                        let endIndex = min(entries.count, nextIndex + workerCount)
                        let batch = entries[nextIndex..<endIndex]
                        var results: [(Int, EntryResult)] = []
                        await withTaskGroup(of: (Int, EntryResult).self) { group in
                            for (offset, url) in batch.enumerated() {
                                let entryIndex = nextIndex + offset
                                group.addTask { (entryIndex, inspectEntry(url, keys: keys, entryIndex: entryIndex)) }
                            }
                            for await result in group { results.append(result) }
                        }
                        let hadAsset = !snapshot.assets.isEmpty
                        let previousExamined = snapshot.examined
                        for (_, result) in results.sorted(by: { $0.0 < $1.0 }) { apply(result) }
                        nextIndex = endIndex
                        // Yield the first usable result immediately, then at measured batches.
                        if (!hadAsset && !snapshot.assets.isEmpty)
                            || previousExamined / 48 != snapshot.examined / 48 {
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

    private func inspectEntry(_ url: URL, keys: Set<URLResourceKey>, entryIndex: Int) -> EntryResult {
        let name = url.lastPathComponent
        if name == "Comprimidas" || name.hasPrefix("Comprimidas-") || name == ".comprime-backups" { return .excluded }
        do {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isPackage != true, values.isRegularFile == true else { return .excluded }
            let eagerLimit = limits.eagerThumbnailCount
            let thumbnailAllowance = entryIndex < eagerLimit && eagerLimit > 0
                ? max(1, limits.thumbnailBudget / eagerLimit)
                : 0
            let asset = try autoreleasepool {
                try inspect(url, values: values, remainingThumbnailBytes: thumbnailAllowance)
            }
            return .asset(asset)
        } catch {
            return .issue(ScanIssue(url: url, reason: error.localizedDescription))
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

private enum EntryResult: Sendable {
    case excluded
    case asset(ImageAsset)
    case issue(ScanIssue)
}
private enum ScanFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
