import Foundation
import StowCore

struct MacLibraryFilterToken: Equatable, Identifiable {
    enum Kind: Equatable {
        case type
        case source
        case date
    }

    let kind: Kind
    let title: String
    var id: Kind { kind }
}

struct MacLibraryFilterSummary: Equatable {
    let tokens: [MacLibraryFilterToken]

    init(type: ItemType?, source: String?, date: DateAddedFilter) {
        var tokens: [MacLibraryFilterToken] = []
        if let type {
            tokens.append(MacLibraryFilterToken(kind: .type, title: type.macLibraryName))
        }
        if let source, !source.isEmpty {
            tokens.append(MacLibraryFilterToken(kind: .source, title: source))
        }
        if date != .anytime {
            tokens.append(MacLibraryFilterToken(kind: .date, title: date.rawValue))
        }
        self.tokens = tokens
    }

    var count: Int { tokens.count }
    var compactLabel: String { count == 1 ? "1 Filter" : "\(count) Filters" }
}

enum MacLibraryEmptyState: Equatable {
    case noResults
    case emptyInbox
    case emptySection(StowSection)
}

enum MacLibraryPinAction: Equatable {
    case pinAll
    case unpinAll

    var title: String {
        switch self {
        case .pinAll: "Pin All"
        case .unpinAll: "Unpin All"
        }
    }

    var systemImage: String {
        switch self {
        case .pinAll: "pin"
        case .unpinAll: "pin.slash"
        }
    }
}

enum MacLibraryLifecycleAction: Equatable {
    case archive
    case restoreToInbox

    var title: String {
        switch self {
        case .archive: "Archive"
        case .restoreToInbox: "Restore to Inbox"
        }
    }
}

enum MacLibraryPolicy {
    static let sections: [StowSection] = [.inbox, .recent, .pinned, .archive, .trash]

    static func title(for section: StowSection) -> String {
        section == .recent ? "Recently Used" : section.rawValue
    }

    static func includes(_ item: StowItem, in section: StowSection) -> Bool {
        switch section {
        case .inbox: item.status == .inbox
        case .recent: item.status != .trashed && item.lastUsedAt != nil
        case .pinned: item.status != .trashed && item.isPinned
        case .archive: item.status == .archived
        case .trash: item.status == .trashed
        case .settings: false
        }
    }

    static func counts(for items: [StowItem]) -> [StowSection: Int] {
        var counts = Dictionary(uniqueKeysWithValues: sections.map { ($0, 0) })
        for item in items {
            for section in sections where includes(item, in: section) {
                counts[section, default: 0] += 1
            }
        }
        return counts
    }

    static func subtitle(for section: StowSection) -> String {
        switch section {
        case .inbox: "Everything you save, ready for what’s next."
        case .recent: "Pick up where you left off."
        case .pinned: "Your essentials, always close at hand."
        case .archive: "Out of the way. Never out of reach."
        case .trash: "Recover items for up to 30 days."
        case .settings: "Make Stow your own."
        }
    }

    static func emptyState(section: StowSection, hasSearchText: Bool, hasFilters: Bool) -> MacLibraryEmptyState {
        if hasSearchText || hasFilters { return .noResults }
        if section == .inbox { return .emptyInbox }
        return .emptySection(section)
    }

    static func pinAction(for items: [StowItem]) -> MacLibraryPinAction? {
        guard !items.isEmpty else { return nil }
        return items.allSatisfy(\.isPinned) ? .unpinAll : .pinAll
    }

    static func lifecycleAction(for items: [StowItem]) -> MacLibraryLifecycleAction? {
        guard let status = items.first?.status, items.allSatisfy({ $0.status == status }) else { return nil }
        switch status {
        case .inbox: return .archive
        case .archived: return .restoreToInbox
        case .trashed: return nil
        }
    }
}

struct MacLibraryEditDraft: Equatable {
    var title: String
    var note: String
    var text: String
    var language: String

    init(item: StowItem) {
        title = item.title
        note = item.note ?? ""
        text = item.textContent ?? ""
        language = item.language ?? ""
    }

    func isDirty(comparedWith item: StowItem) -> Bool {
        title != item.title ||
            note != (item.note ?? "") ||
            text != (item.textContent ?? "") ||
            language != (item.language ?? "")
    }
}

private extension ItemType {
    var macLibraryName: String {
        switch self {
        case .link: "Links"
        case .text: "Text"
        case .code: "Code"
        case .image: "Images"
        case .file: "Files"
        }
    }
}
