import Foundation
import StowCore

/// Local fallback uses per-field substrings, not the index's token/prefix query language.
enum LocalItemSearch {
    static func matchesMetadata(
        _ item: StowItem, type: ItemType?, source: String?, date: DateAddedFilter,
        now: Date = Date(), calendar: Calendar = .current
    ) -> Bool {
        (type == nil || item.type == type) &&
            (source == nil || item.sourceApp == source) &&
            date.includes(item.createdAt, now: now, calendar: calendar)
    }

    static func matchesText(_ item: StowItem, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let query = normalizeWidth(query)
        return [item.title, item.textContent, item.urlString, item.sourceDomain, item.note, item.fileName]
            .compactMap { $0 }
            .contains { normalizeWidth($0).localizedCaseInsensitiveContains(query) }
    }

    private static func normalizeWidth(_ value: String) -> String {
        value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value
    }
}
