import Foundation
import CryptoKit
import Darwin

public struct BatchItem: Identifiable, Sendable {
    public var id: URL { source }
    public let source: URL
    public let output: URL?
    public let originalBytes: Int64
    public let outputBytes: Int64
    public let targetMet: Bool
    public let message: String
    public let warnings: [String]
}
public struct BatchSnapshot: Sendable {
    public var total = 0
    public var items: [BatchItem] = []
    public var outputFolder: URL?
    public var backupFolder: URL?
    public var finished = false
    public var cancelled = false
    public init() {}
    public var before: Int64 { items.filter { $0.output != nil }.reduce(0) { $0 + $1.originalBytes } }
    public var after: Int64 { items.filter { $0.output != nil }.reduce(0) { $0 + $1.outputBytes } }
}

public final class BatchControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

public struct BatchProcessor: Sendable {
    public init() {}
    public func run(folder: URL, assets: [ImageAsset], request: CompressionRequest, replaceOriginals: Bool = false, control: BatchControl = BatchControl()) -> AsyncThrowingStream<BatchSnapshot, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                do {
                    if replaceOriginals { guard case .preserve = request.outputMode else { throw EngineFailure.message("Reemplazar originales requiere mantener el formato.") } }
                    var snapshot = BatchSnapshot()
                    snapshot.total = assets.count
                    if replaceOriginals {
                        let base = folder.appendingPathComponent(".comprime-backups", isDirectory: true)
                        if FileManager.default.fileExists(atPath: base.path) {
                            let info = try base.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                            guard info.isDirectory == true, info.isSymbolicLink != true else { throw EngineFailure.message("La ruta de respaldos no es una carpeta segura.") }
                        } else { try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false) }
                        snapshot.backupFolder = try createUniqueDirectory(in: base, name: UUID().uuidString)
                        snapshot.outputFolder = folder
                    } else { snapshot.outputFolder = try createUniqueDirectory(in: folder, name: "Comprimidas") }
                    continuation.yield(snapshot)
                    let output = snapshot.outputFolder!, backup = snapshot.backupFolder
                    // Bound peak raster memory: large images are processed one at a time.
                    let parallelism = assets.contains { Int64($0.width) * Int64($0.height) > 20_000_000 } ? 1 : 2
                    await withTaskGroup(of: BatchItem.self) { group in
                        var next = 0
                        func enqueue(_ asset: ImageAsset) {
                            group.addTask {
                                do {
                                    try Task.checkCancellation()
                                    let hash = SHA256.hash(data: try Data(contentsOf: asset.url, options: .mappedIfSafe))
                                    if control.isCancelled { throw CancellationError() }
                                    let candidate = try await LocalCompressionEngine().compress(asset, request: request)
                                    defer { discard(candidate) }
                                    if control.isCancelled { throw CancellationError() }
                                    try Task.checkCancellation()
                                    try verifyUnchanged(asset.url, hash: hash)
                                    let saved: URL
                                    if let backup {
                                        guard candidate.bytes < asset.bytes, candidate.bytes <= request.targetBytes else {
                                            return BatchItem(source: asset.url, output: nil, originalBytes: asset.bytes, outputBytes: 0,
                                                targetMet: false, message: "Original conservado: no hay una reducción que cumpla el objetivo.", warnings: candidate.warnings)
                                        }
                                        saved = try replaceSafely(asset: asset, candidate: candidate, backup: backup, expected: hash)
                                    } else { saved = try publish(candidate: candidate, asset: asset, directory: output) }
                                    return BatchItem(source: asset.url, output: saved, originalBytes: asset.bytes, outputBytes: candidate.bytes,
                                        targetMet: candidate.bytes <= request.targetBytes,
                                        message: candidate.bytes <= request.targetBytes ? (candidate.bytes == asset.bytes ? "Sin cambios" : "Comprimida") : "No alcanzó objetivo",
                                        warnings: candidate.warnings)
                                } catch {
                                    return BatchItem(source: asset.url, output: nil, originalBytes: asset.bytes, outputBytes: 0, targetMet: false,
                                        message: (Task.isCancelled || control.isCancelled) ? "Cancelada" : friendly(error), warnings: [])
                                }
                            }
                        }
                        while next < min(parallelism, assets.count) { enqueue(assets[next]); next += 1 }
                        while let item = await group.next() {
                            snapshot.items.append(item)
                            continuation.yield(snapshot)
                            if Task.isCancelled || control.isCancelled { group.cancelAll() }
                            else if next < assets.count { enqueue(assets[next]); next += 1 }
                        }
                    }
                    snapshot.finished = true
                    snapshot.cancelled = Task.isCancelled || control.isCancelled || snapshot.items.count < assets.count
                    continuation.yield(snapshot)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

private func createUniqueDirectory(in parent: URL, name: String) throws -> URL {
    for suffix in 0..<10000 {
        let url = parent.appendingPathComponent(suffix == 0 ? name : "\(name)-\(suffix + 1)", isDirectory: true)
        if mkdir(url.path, 0o700) == 0 { return url }
        guard errno == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    throw EngineFailure.message("No fue posible reservar una carpeta de salida.")
}
private func publish(candidate: CompressionCandidate, asset: ImageAsset, directory: URL) throws -> URL {
    let fm = FileManager.default
    let staging = directory.appendingPathComponent(".comprime-\(UUID().uuidString).tmp")
    try fm.copyItem(at: candidate.temporaryURL, to: staging)
    defer { try? fm.removeItem(at: staging) }
    let bytes = try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard Int64(bytes) == candidate.bytes else { throw CompressionError.encodeFailed }
    try Task.checkCancellation()
    let basename = asset.url.deletingPathExtension().lastPathComponent
    let ext = candidate.format == asset.format ? asset.url.pathExtension : candidate.format.fileExtension
    for suffix in 0..<10000 {
        let name = suffix == 0 ? basename : "\(basename)-\(suffix + 1)"
        let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
        // Hard link publishes the complete same-volume staging file exclusively; EEXIST never overwrites.
        if link(staging.path, url.path) == 0 { return url }
        guard errno == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    throw EngineFailure.message("Demasiados archivos con el mismo nombre de salida.")
}
private func replaceSafely(asset: ImageAsset, candidate: CompressionCandidate, backup: URL, expected: SHA256.Digest) throws -> URL {
    let fm = FileManager.default
    let attributes = try fm.attributesOfItem(atPath: asset.url.path)
    guard (attributes[.referenceCount] as? Int ?? 1) == 1,
          candidate.format == asset.format || (candidate.format == .heic && asset.format == .heif) else {
        throw EngineFailure.message("No se reemplazan enlaces ni archivos cuyo formato cambiaría.")
    }
    let backupURL = backup.appendingPathComponent(asset.url.lastPathComponent)
    try fm.copyItem(at: asset.url, to: backupURL)
    guard SHA256.hash(data: try Data(contentsOf: backupURL, options: .mappedIfSafe)) == expected else {
        throw EngineFailure.message("No se pudo verificar el respaldo. Original conservado.")
    }
    let manifest = backup.appendingPathComponent("\(UUID().uuidString).json")
    var record = ["source": asset.url.path, "backup": backupURL.path,
                  "sha256": expected.map { String(format: "%02x", $0) }.joined(), "state": "backupVerified"]
    try JSONSerialization.data(withJSONObject: record, options: .prettyPrinted).write(to: manifest, options: .atomic)
    let staging = asset.url.deletingLastPathComponent().appendingPathComponent(".comprime-\(UUID().uuidString).tmp")
    try fm.copyItem(at: candidate.temporaryURL, to: staging)
    defer { try? fm.removeItem(at: staging) }
    try Task.checkCancellation()
    try verifyUnchanged(asset.url, hash: expected)
    // Atomic rename swaps only after the verified independent backup is durable on disk.
    let backupFD = open(backupURL.path, O_RDONLY)
    guard backupFD >= 0 else { throw EngineFailure.message("No se pudo abrir el respaldo para sincronizarlo.") }
    let syncStatus = fsync(backupFD)
    close(backupFD)
    guard syncStatus == 0 else { throw EngineFailure.message("No se pudo sincronizar el respaldo.") }
    guard rename(staging.path, asset.url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    record["state"] = "replaced"
    try? JSONSerialization.data(withJSONObject: record, options: .prettyPrinted).write(to: manifest, options: .atomic)
    return asset.url
}
public func friendly(_ error: Error) -> String {
    if error is CancellationError { return "Cancelada" }
    if let error = error as? CompressionError {
        switch error {
        case .changedSource: return "El archivo cambió. Vuelve a abrir la carpeta."
        case .invalidTarget: return "Introduce un objetivo mayor que cero."
        case .unsupportedContent: return "Contenido no compatible."
        case .insufficientMemory: return "No hay memoria suficiente para procesar esta imagen."
        case .encodeFailed: return "No se pudo codificar o verificar la imagen."
        case .cancelled: return "Cancelada"
        }
    }
    return error.localizedDescription
}
