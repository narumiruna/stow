import Foundation
import StowCore

struct ItemCardPresentation {
    let title: String
    let excerpt: String?
    let source: String

    init(item: StowItem) {
        let typeName = Self.typeName(for: item.type)
        let sourceApp = Self.normalized(item.sourceApp)
        let domain = Self.normalized(item.sourceDomain)
        let url = Self.normalized(item.urlString)
        let host = Self.normalized(url.flatMap { URL(string: $0)?.host })
        let fileName = Self.normalized(item.fileName)
        let fallbackTitle = item.type == .link ? (domain ?? host) : fileName
        let title = Self.normalized(item.displayTitle) ?? fallbackTitle ?? typeName
        self.title = title
        source = item.type == .link
            ? domain ?? host ?? sourceApp ?? typeName
            : sourceApp ?? typeName

        let candidates: [String?]
        switch item.type {
        case .link:
            candidates = [item.displayLinkDescription, item.note]
        case .text, .code:
            candidates = [item.textContent, item.note]
        case .image, .file:
            candidates = [item.note, fileName]
        }

        var excluded = [title]
        if item.type == .link {
            excluded.append(contentsOf: [url, domain, host].compactMap { $0 })
        }
        var excerpt: String?
        for candidate in candidates {
            guard let candidate, let normalized = Self.normalized(candidate),
                  !excluded.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else { continue }
            excerpt = item.type == .code && candidate == item.textContent
                ? candidate.trimmingCharacters(in: .newlines) : normalized
            break
        }
        self.excerpt = excerpt.map(Self.boundedExcerpt)
    }

    private static func boundedExcerpt(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let preview = String(lines.prefix(4).joined(separator: "\n").prefix(160))
        return preview.count < text.count ? preview + "…" : preview
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    private static func typeName(for type: ItemType) -> String {
        switch type {
        case .link: "Link"
        case .text: "Note"
        case .code: "Code"
        case .image: "Image"
        case .file: "File"
        }
    }
}
