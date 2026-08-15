import Foundation

public struct ParsedHTMLMetadata: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var previewImageURL: URL?
    public var faviconURL: URL?

    public init(title: String? = nil, description: String? = nil, previewImageURL: URL? = nil, faviconURL: URL? = nil) {
        self.title = title
        self.description = description
        self.previewImageURL = previewImageURL
        self.faviconURL = faviconURL
    }
}

public enum HTMLMetadataParser {
    public static func parse(_ html: String, baseURL: URL) -> ParsedHTMLMetadata {
        let metaTags = matches(pattern: #"<meta\b[^>]*>"#, in: html)
        let linkTags = matches(pattern: #"<link\b[^>]*>"#, in: html)
        var metadata: [String: String] = [:]
        for tag in metaTags {
            let attributes = attributes(in: tag)
            if let key = (attributes["property"] ?? attributes["name"])?.lowercased(), let content = attributes["content"] {
                metadata[key] = decodeCharacterReferences(content)
            }
        }

        let htmlTitle = firstMatch(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html, capture: 1).map { decodeCharacterReferences(stripTags($0)) }
        let title = clean(metadata["og:title"]) ?? clean(htmlTitle)
        let description = clean(metadata["og:description"]) ?? clean(metadata["description"])
        let image = clean(metadata["og:image"]).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }

        var favicon: URL?
        for tag in linkTags {
            let attributes = attributes(in: tag)
            if attributes["rel"]?.lowercased().split(separator: " ").contains(where: { $0.contains("icon") }) == true,
               let href = attributes["href"] {
                favicon = URL(string: decodeCharacterReferences(href), relativeTo: baseURL)?.absoluteURL
                break
            }
        }
        return ParsedHTMLMetadata(title: title, description: description, previewImageURL: image, faviconURL: favicon)
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueIndex = match.range(at: 2).location != NSNotFound ? 2 : 3
            guard let valueRange = Range(match.range(at: valueIndex), in: tag) else { continue }
            result[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }
        return result
    }

    private static func matches(pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            Range(match.range, in: string).map { String(string[$0]) }
        }
    }

    private static func firstMatch(pattern: String, in string: String, capture: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..<string.endIndex, in: string)),
              let range = Range(match.range(at: capture), in: string) else { return nil }
        return String(string[range])
    }

    private static func stripTags(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    public static func decodeCharacterReferences(_ value: String) -> String {
        var output = value
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        let numeric = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-F]+)|(\d+));"#, options: .caseInsensitive)
        if let numeric {
            for match in numeric.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed() {
                let isHexadecimal = match.range(at: 1).location != NSNotFound
                let digitsIndex = isHexadecimal ? 1 : 2
                guard let full = Range(match.range(at: 0), in: output),
                      let digits = Range(match.range(at: digitsIndex), in: output),
                      let scalarValue = UInt32(output[digits], radix: isHexadecimal ? 16 : 10),
                      let scalar = UnicodeScalar(scalarValue) else { continue }
                output.replaceSubrange(full, with: String(Character(scalar)))
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
