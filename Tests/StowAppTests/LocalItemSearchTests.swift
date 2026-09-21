import XCTest
import StowCore
@testable import StowApp

final class LocalItemSearchTests: XCTestCase {
    func testEachSearchableFieldUsesWidthNormalizedCaseInsensitiveSubstrings() {
        let setters: [(StowItem, String) -> Void] = [
            { $0.title = $1 }, { $0.textContent = $1 }, { $0.urlString = $1 },
            { $0.sourceDomain = $1 }, { $0.note = $1 }, { $0.fileName = $1 },
        ]
        for set in setters {
            let item = StowItem(type: .text, title: "")
            set(item, "Ｓｗｉｆｔ　Concurrency：１２３")
            for query in ["", "swift concurrency:123", "ＵＲＲＥＮＣＹ", ":12"] {
                XCTAssertTrue(LocalItemSearch.matchesText(item, query: query), query)
            }
            for query in ["concurrency swift", "swift  concurrency", "currency!"] {
                XCTAssertFalse(LocalItemSearch.matchesText(item, query: query), query)
            }
        }
    }

    func testDoesNotJoinFieldsOrSearchUnlistedMetadata() {
        let item = StowItem(type: .code, title: "Swift", textContent: "concurrency")
        item.sourceApp = "ExcludedApp"
        item.language = "ExcludedLanguage"
        item.linkDescription = "ExcludedDescription"
        for query in ["Swift concurrency", "Swift\nconcurrency", "Excluded"] {
            XCTAssertFalse(LocalItemSearch.matchesText(item, query: query))
        }
        XCTAssertTrue(LocalItemSearch.matchesText(item, query: "currency"))
    }

    func testMetadataPreservesExactSourceAndOptionalTypeFilters() {
        let item = StowItem(type: .text, title: "")
        item.sourceApp = "Safari"
        for (type, source, expected) in [
            (nil, nil, true), (ItemType.text, "Safari", true), (.code, "Safari", false),
            (.text, "safari", false), (.text, "", false),
        ] as [(ItemType?, String?, Bool)] {
            XCTAssertEqual(LocalItemSearch.matchesMetadata(item, type: type, source: source, date: .anytime), expected)
        }
        item.sourceApp = nil
        XCTAssertTrue(LocalItemSearch.matchesMetadata(item, type: nil, source: nil, date: .anytime))
        XCTAssertFalse(LocalItemSearch.matchesMetadata(item, type: nil, source: "", date: .anytime))
    }

    func testDateBoundariesUseExistingCalendarPolicyIncludingFutureDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))!
        let item = StowItem(type: .text, title: "")
        for (filter, boundary) in [
            (DateAddedFilter.today, calendar.startOfDay(for: now)),
            (.week, calendar.date(byAdding: .day, value: -7, to: now)!),
            (.month, calendar.date(byAdding: .month, value: -1, to: now)!),
        ] {
            for (date, expected) in [(boundary.addingTimeInterval(-1), false), (boundary, true), (now.addingTimeInterval(60), true)] {
                item.createdAt = date
                XCTAssertEqual(LocalItemSearch.matchesMetadata(item, type: nil, source: nil, date: filter, now: now, calendar: calendar), expected)
            }
        }
        item.createdAt = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertFalse(LocalItemSearch.matchesMetadata(item, type: nil, source: nil, date: .today, now: now, calendar: calendar))
        XCTAssertTrue(LocalItemSearch.matchesMetadata(item, type: nil, source: nil, date: .week, now: now, calendar: calendar))
    }
}
