import XCTest
import Foundation
import ImageIO
import CoreGraphics
@testable import ComprimeCore

final class FolderScannerTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func makePNG(_ url: URL) throws {
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 0.4, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    private func scan(_ url: URL, limits: ScanLimits = ScanLimits()) async throws -> ScanSnapshot {
        var last = ScanSnapshot()
        for try await update in FolderScanner(limits: limits).scan(url) { last = update }
        return last
    }
    func testContentDetectionExclusionsAndNoSourceMutation() async throws {
        let root = try makeDirectory()
        let file = root.appendingPathComponent("image.wrong")
        try makePNG(file)
        let before = try Data(contentsOf: file)
        try makePNG(root.appendingPathComponent(".hidden.png"))
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try makePNG(nested.appendingPathComponent("nested.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: file)
        try Data("broken".utf8).write(to: root.appendingPathComponent("broken.jpg"))
        let result = try await scan(root)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.assets.count, 1)
        XCTAssertEqual(result.assets.first?.format, .png)
        XCTAssertEqual(result.assets.first?.width, 32)
        XCTAssertEqual(result.assets.first?.hasAlphaChannel, true)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.excluded, 2)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testPixelLimitAndThumbnailBudget() async throws {
        let root = try makeDirectory()
        try makePNG(root.appendingPathComponent("image.png"))
        let rejected = try await scan(root, limits: ScanLimits(maxPixels: 100))
        XCTAssertEqual(rejected.assets.count, 0)
        XCTAssertEqual(rejected.issues.count, 1)
        let noThumbnails = try await scan(root, limits: ScanLimits(thumbnailBudget: 0))
        XCTAssertEqual(noThumbnails.assets.count, 1)
        XCTAssertNil(noThumbnails.assets.first?.thumbnail)
    }
    func testEmptyFolderAndInvalidTarget() async throws {
        let result = try await scan(makeDirectory())
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.assets.isEmpty)
        XCTAssertThrowsError(try CompressionRequest(targetBytes: 0))
        XCTAssertThrowsError(try CompressionRequest(targetBytes: -1))
        XCTAssertNoThrow(try CompressionRequest(targetBytes: 1_000_000))
    }
    func testMissingFolderFails() async {
        do {
            _ = try await scan(URL(fileURLWithPath: "/nonexistent-comprime-\(UUID().uuidString)"))
            XCTFail("Missing folders must fail")
        } catch { }
    }
}
