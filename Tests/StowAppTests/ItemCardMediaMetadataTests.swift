import CoreGraphics
import ImageIO
import XCTest
@testable import StowApp

final class ItemCardMediaMetadataTests: XCTestCase {
    func testLandscapeImageReservesItsStoredRatio() throws {
        let data = try image(width: 360, height: 283)
        XCTAssertEqual(try XCTUnwrap(ItemCardMediaMetadata.aspectRatio(in: data)), 360.0 / 283, accuracy: 0.0001)
    }

    func testPortraitImageReservesItsStoredRatio() throws {
        let data = try image(width: 360, height: 438)
        XCTAssertEqual(try XCTUnwrap(ItemCardMediaMetadata.aspectRatio(in: data)), 360.0 / 438, accuracy: 0.0001)
    }

    func testSquareImageReservesASquare() throws {
        XCTAssertEqual(ItemCardMediaMetadata.aspectRatio(in: try image(width: 128, height: 128)), 1)
    }

    func testWideImagesUseTheExistingMaximumRatio() throws {
        XCTAssertEqual(ItemCardMediaMetadata.aspectRatio(in: try image(width: 1000, height: 100)), 1.8)
    }

    func testTallImagesUseTheExistingMinimumRatio() throws {
        XCTAssertEqual(ItemCardMediaMetadata.aspectRatio(in: try image(width: 100, height: 1000)), 0.75)
    }

    func testRotatedAndRotatedMirroredImagesSwapDimensions() throws {
        for orientation in 5...8 {
            let data = try image(width: 120, height: 100, orientation: orientation)
            XCTAssertEqual(try XCTUnwrap(ItemCardMediaMetadata.aspectRatio(in: data)), 100.0 / 120, accuracy: 0.0001)
        }
    }

    func testUnrotatedAndMirroredImagesKeepDimensions() throws {
        for orientation in 1...4 {
            let data = try image(width: 120, height: 100, orientation: orientation)
            XCTAssertEqual(try XCTUnwrap(ItemCardMediaMetadata.aspectRatio(in: data)), 1.2, accuracy: 0.0001)
        }
    }

    func testMissingOrInvalidImageHeadersHaveNoMediaFrame() {
        for data in [Data(), Data("not an image".utf8), Data([0x49, 0x49, 0x2A, 0x00])] {
            XCTAssertNil(ItemCardMediaMetadata.aspectRatio(in: data))
        }
    }

    private func image(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
