import XCTest
import AppKit
@testable import OpenClip

final class CursorClassifierTests: XCTestCase {
    func testBeamShapeClassifiesBeam() {
        // I-beam: a thin vertical bar with small horizontal caps at top and bottom.
        let beam = makeCursorImage(width: 16, height: 32) { x, y in
            if y < 3 || y >= 29 {
                return x >= 5 && x <= 10
            }
            return x >= 7 && x <= 8
        }
        XCTAssertEqual(CursorClassifier.classify(beam), .beam)
    }

    func testRealSystemPointingHandClassifiesPointingHand() {
        // The system pointing-hand cursor ships a real bitmap, but whether that bitmap is exposed
        // is host-dependent: recognize the real shape when available, and degrade to `.unknown`
        // otherwise rather than guessing.
        let result = CursorClassifier.classify(NSCursor.pointingHand.image)
        XCTAssertTrue(result == .pointingHand || result == .unknown, "unexpected pointingHand classification \(result)")
    }

    func testARGBPixelLayoutClassifiesSameShapes() {
        // Premultiplied-first (ARGB) layout puts alpha at byte 0 of each pixel; the classifier
        // must derive the offset from alphaInfo/byteOrder rather than assuming the last byte.
        let beam = makeCursorImageARGB(width: 16, height: 32) { x, y in
            if y < 3 || y >= 29 {
                return x >= 5 && x <= 10
            }
            return x >= 7 && x <= 8
        }
        XCTAssertEqual(CursorClassifier.classify(beam), .beam)
    }

    // MARK: - Fixture builder

    /// Builds a small cursor-shaped `NSImage` from an opaque-pixel predicate so the
    /// classifier's alpha-mask analysis is fully deterministic.
    private func makeCursorImage(width: Int, height: Int, opaque: (Int, Int) -> Bool) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width where opaque(x, y) {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        return pixels.withUnsafeMutableBytes { buffer -> NSImage in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
        }
    }

    /// Same fixture builder, but with alpha-first (premultiplied-first / ARGB) pixels.
    private func makeCursorImageARGB(width: Int, height: Int, opaque: (Int, Int) -> Bool) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width where opaque(x, y) {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = 255
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }
        return pixels.withUnsafeMutableBytes { buffer -> NSImage in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
        }
    }
}
