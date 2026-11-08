import XCTest
@testable import StowApp

final class GalleryPageTests: XCTestCase {
    func testCapacityBoundsEachRenderedPageToFortyCards() {
        XCTAssertEqual(GalleryPage.capacity, 40)
    }

    func testEmptyResultsHaveOneEmptyPageAndNoNavigation() {
        for count in [-1, 0] {
            let page = GalleryPage(itemCount: count, index: 4)
            XCTAssertEqual(page.index, 0)
            XCTAssertEqual(page.count, 1)
            XCTAssertEqual(page.range, 0..<0)
            XCTAssertFalse(page.hasPrevious)
            XCTAssertFalse(page.hasNext)
        }
    }

    func testSmallResultsDoNotNeedPagination() {
        for count in [1, 39, 40] {
            let page = GalleryPage(itemCount: count, index: 0)
            XCTAssertEqual(page.count, 1)
            XCTAssertEqual(page.range, 0..<count)
            XCTAssertFalse(page.hasPrevious)
            XCTAssertFalse(page.hasNext)
        }
    }

    func testPartialFinalPageReplacesRatherThanAccumulatesCards() {
        let first = GalleryPage(itemCount: 81, index: 0)
        let second = GalleryPage(itemCount: 81, index: 1)
        let last = GalleryPage(itemCount: 81, index: 2)
        XCTAssertEqual(first.range, 0..<40)
        XCTAssertEqual(second.range, 40..<80)
        XCTAssertEqual(last.range, 80..<81)
        XCTAssertEqual(last.count, 3)
        XCTAssertFalse(first.hasPrevious)
        XCTAssertTrue(first.hasNext)
        XCTAssertTrue(second.hasPrevious)
        XCTAssertTrue(second.hasNext)
        XCTAssertTrue(last.hasPrevious)
        XCTAssertFalse(last.hasNext)
    }

    func testExactPageBoundaryDoesNotCreateAnEmptyFinalPage() {
        let page = GalleryPage(itemCount: 80, index: 1)
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.range, 40..<80)
        XCTAssertTrue(page.hasPrevious)
        XCTAssertFalse(page.hasNext)
    }

    func testInvalidIndexClampsToTheAvailablePages() {
        XCTAssertEqual(GalleryPage(itemCount: 81, index: -1).index, 0)
        XCTAssertEqual(GalleryPage(itemCount: 81, index: Int.max).index, 2)
        XCTAssertEqual(GalleryPage(itemCount: 81, index: Int.max).range, 80..<81)
    }

    func testRemovingTheOnlyItemOnTheLastPageSelectsThePreviousPage() {
        let before = GalleryPage(itemCount: 81, index: 2)
        let after = GalleryPage(itemCount: 80, index: before.index)
        XCTAssertEqual(after.index, 1)
        XCTAssertEqual(after.range, 40..<80)
        XCTAssertEqual(GalleryPage(itemCount: 82, index: after.index).range, 40..<80)
        XCTAssertEqual(GalleryPage(itemCount: 0, index: after.index).range, 0..<0)
    }

    func testAllPagesCoverEveryOrderedResultExactlyOnce() {
        for count in [0, 1, 39, 40, 41, 79, 80, 81, 100_003] {
            let first = GalleryPage(itemCount: count, index: 0)
            var previousEnd = 0
            for index in 0..<first.count {
                let page = GalleryPage(itemCount: count, index: index)
                XCTAssertEqual(page.range.lowerBound, previousEnd)
                XCTAssertLessThanOrEqual(page.range.count, GalleryPage.capacity)
                XCTAssertEqual(page.hasPrevious, index > 0)
                XCTAssertEqual(page.hasNext, index + 1 < first.count)
                previousEnd = page.range.upperBound
            }
            XCTAssertEqual(previousEnd, count)
        }
    }

    func testRangeUsesLiveResultsWithoutCachingTheirMembership() {
        var results = Array(0..<81)
        let page = GalleryPage(itemCount: results.count, index: 1)
        XCTAssertEqual(Array(results[page.range]), Array(40..<80))
        results.reverse()
        XCTAssertEqual(Array(results[page.range]), Array((1...40).reversed()))
        results.removeLast(41)
        let clamped = GalleryPage(itemCount: results.count, index: page.index)
        XCTAssertEqual(clamped.index, 0)
        XCTAssertEqual(Array(results[clamped.range]), Array((41...80).reversed()))
    }

    func testVeryLargeCountDoesNotOverflowTheFinalRange() {
        let page = GalleryPage(itemCount: Int.max, index: Int.max)
        XCTAssertEqual(page.range.upperBound, Int.max)
        XCTAssertLessThanOrEqual(page.range.count, GalleryPage.capacity)
        XCTAssertFalse(page.hasNext)
    }
}
