import Foundation

public enum ImageFormat: String, CaseIterable, Sendable {
    case jpeg = "JPEG", png = "PNG", heic = "HEIC", heif = "HEIF", webp = "WebP"
    public init?(typeIdentifier: String) {
        switch typeIdentifier {
        case "public.jpeg": self = .jpeg
        case "public.png": self = .png
        case "public.heic": self = .heic
        case "public.heif": self = .heif
        case "org.webmproject.webp": self = .webp
        default: return nil
        }
    }
}

public struct ImageAsset: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let format: ImageFormat
    public let bytes: Int64
    public let width: Int
    public let height: Int
    public let orientation: Int
    public let hasAlphaChannel: Bool
    public let colorProfile: String?
    public let modifiedAt: Date?
    public let thumbnail: Data?
}

public struct ScanIssue: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let reason: String
}

public struct ScanSnapshot: Sendable {
    public var assets: [ImageAsset] = []
    public var issues: [ScanIssue] = []
    public var examined = 0
    public var excluded = 0
    public var isComplete = false
    public init() {}
    public var totalBytes: Int64 { assets.reduce(0) { $0 + $1.bytes } }
}

public struct ScanLimits: Sendable {
    public let maxPixels: Int64
    public let maxSourceBytes: Int64
    public let thumbnailEdge: Int
    public let thumbnailBudget: Int
    public init(maxPixels: Int64 = 80_000_000, maxSourceBytes: Int64 = 250_000_000,
                thumbnailEdge: Int = 96, thumbnailBudget: Int = 24_000_000) {
        self.maxPixels = maxPixels
        self.maxSourceBytes = maxSourceBytes
        self.thumbnailEdge = thumbnailEdge
        self.thumbnailBudget = thumbnailBudget
    }
}

public enum OutputMode: Sendable { case preserve, automatic, convert(ImageFormat) }
public enum MetadataPolicy: Sendable { case preserve, remove }
public struct CompressionRequest: Sendable {
    public let targetBytes: Int64
    public let outputMode: OutputMode
    public let metadataPolicy: MetadataPolicy
    public let removeGPS: Bool
    public let allowResize: Bool
    public init(targetBytes: Int64, outputMode: OutputMode = .preserve,
                metadataPolicy: MetadataPolicy = .preserve, removeGPS: Bool = false,
                allowResize: Bool = true) throws {
        guard targetBytes > 0 else { throw CompressionError.invalidTarget }
        self.targetBytes = targetBytes
        self.outputMode = outputMode
        self.metadataPolicy = metadataPolicy
        self.removeGPS = removeGPS
        self.allowResize = allowResize
    }
}
public enum CompressionError: Error, Sendable {
    case invalidTarget, unsupportedContent, changedSource, insufficientMemory, encodeFailed, cancelled
}
public struct CompressionCandidate: Sendable {
    public let temporaryURL: URL
    public let bytes: Int64
    public let width: Int
    public let height: Int
    public let format: ImageFormat
    public let quality: Double?
    public let warnings: [String]
}
public protocol ImageEncoder: Sendable {
    var format: ImageFormat { get }
    func encode(source: ImageAsset, request: CompressionRequest, quality: Double?,
                width: Int, height: Int, temporaryURL: URL) async throws -> CompressionCandidate
}
public protocol CompressionEngine: Sendable {
    func compress(_ source: ImageAsset, request: CompressionRequest) async throws -> CompressionCandidate
}
