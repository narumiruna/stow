import Foundation
import SwiftUI
import StowCore

extension ItemType {
    var displayName: String {
        switch self {
        case .link: "Links"
        case .text: "Text"
        case .code: "Code"
        case .image: "Images"
        case .file: "Files"
        }
    }

    var icon: String {
        switch self {
        case .link: "link"
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var tint: Color {
        switch self {
        case .link: .blue
        case .text: .teal
        case .code: .purple
        case .image: .pink
        case .file: .orange
        }
    }
}

extension StowItem {
    var displayTitle: String {
        type == .link ? HTMLMetadataParser.decodeCharacterReferences(title) : title
    }

    var displayLinkDescription: String? {
        linkDescription.map(HTMLMetadataParser.decodeCharacterReferences)
    }

    var previewText: String {
        switch type {
        case .link: sourceDomain ?? urlString ?? "Link"
        case .text, .code: textContent ?? ""
        case .image: fileName ?? "Image"
        case .file: fileName ?? "File"
        }
    }
}

enum SimpleSyntaxHighlighter {
    static func highlight(_ source: String) -> AttributedString {
        var result = AttributedString(source)
        result.font = .system(.body, design: .monospaced)
        apply(#"\b(?:let|var|func|class|struct|enum|if|else|for|while|return|import|public|private|async|await|throws)\b"#, color: .purple, bold: true, source: source, result: &result)
        apply(#"\b\d+(?:\.\d+)?\b"#, color: .orange, source: source, result: &result)
        apply(#"\"(?:\\.|[^\"\\])*\""#, color: .green, source: source, result: &result)
        apply(#"//[^\n]*|/\*[\s\S]*?\*/"#, color: .secondary, source: source, result: &result)
        return result
    }

    private static func apply(
        _ pattern: String,
        color: Color,
        bold: Bool = false,
        source: String,
        result: inout AttributedString
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        for match in matches {
            guard let sourceRange = Range(match.range, in: source),
                  let lower = AttributedString.Index(sourceRange.lowerBound, within: result),
                  let upper = AttributedString.Index(sourceRange.upperBound, within: result) else { continue }
            let range = lower..<upper
            result[range].foregroundColor = color
            if bold { result[range].font = .system(.body, design: .monospaced).bold() }
        }
    }
}
