import SwiftUI
import XCTest
@testable import StowApp

final class MasonryLayoutTests: XCTestCase {
    func testEmptyGalleryHasNoExtraVerticalSpace() {
        let arrangement = MasonryArrangement(width: 360, columns: 2, spacing: 12, heights: [])
        XCTAssertEqual(arrangement.frames, [])
        XCTAssertEqual(arrangement.size, CGSize(width: 360, height: 0))
    }

    func testCardsUseEqualColumnWidthsAndTheShortestColumn() {
        let arrangement = MasonryArrangement(width: 372, columns: 2, spacing: 12, heights: [300, 120, 180, 100])
        XCTAssertEqual(arrangement.frames, [
            CGRect(x: 0, y: 0, width: 180, height: 300),
            CGRect(x: 192, y: 0, width: 180, height: 120),
            CGRect(x: 192, y: 132, width: 180, height: 180),
            CGRect(x: 0, y: 312, width: 180, height: 100)
        ])
        XCTAssertEqual(arrangement.size, CGSize(width: 372, height: 412))
    }

    func testSingleColumnKeepsReadingOrderAndSpacing() {
        let arrangement = MasonryArrangement(width: 296, columns: 1, spacing: 12, heights: [240, 160, 100])
        XCTAssertEqual(arrangement.frames, [
            CGRect(x: 0, y: 0, width: 296, height: 240),
            CGRect(x: 0, y: 252, width: 296, height: 160),
            CGRect(x: 0, y: 424, width: 296, height: 100)
        ])
        XCTAssertEqual(arrangement.size.height, 524)
    }

    func testEqualHeightsPreserveLeftToRightOrder() {
        let arrangement = MasonryArrangement(width: 332, columns: 2, spacing: 12, heights: [100, 100, 100, 100])
        XCTAssertEqual(arrangement.frames.map(\.origin), [
            CGPoint(x: 0, y: 0), CGPoint(x: 172, y: 0),
            CGPoint(x: 0, y: 112), CGPoint(x: 172, y: 112)
        ])
        XCTAssertEqual(arrangement.size.height, 212)
    }

    func testChangingWidthRecalculatesColumnsWithoutOverlap() {
        for width in [CGFloat(340), 393, 600] {
            let arrangement = MasonryArrangement(width: width, columns: 2, spacing: 12, heights: [400, 160, 200, 80, 300])
            XCTAssertEqual(arrangement.frames.map(\.width), Array(repeating: (width - 12) / 2, count: 5))
            for (index, frame) in arrangement.frames.enumerated() {
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width)
                for other in arrangement.frames.dropFirst(index + 1) {
                    XCTAssertFalse(frame.intersects(other), "Masonry cards must not overlap")
                }
            }
        }
    }

    func testInvalidColumnCountFallsBackToOneColumn() {
        let arrangement = MasonryArrangement(width: 300, columns: 0, spacing: 12, heights: [80, 120])
        XCTAssertEqual(arrangement.frames.map(\.width), [300, 300])
        XCTAssertEqual(arrangement.frames.map(\.minY), [0, 92])
        XCTAssertEqual(arrangement.size.height, 212)
    }
}
