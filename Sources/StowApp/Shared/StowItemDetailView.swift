import QuickLook
import SwiftData
import SwiftUI
import StowCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct StowItemDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var allAttachments: [StowAttachment]
    let item: StowItem
    @State private var title: String
    @State private var note: String
    @State private var text: String
    @State private var language: String
    @State private var editing = false
    @State private var previewURL: URL?
    @State private var imageScale: CGFloat = 1

    init(item: StowItem) {
        self.item = item
        _title = State(initialValue: item.displayTitle)
        _note = State(initialValue: item.note ?? "")
        _text = State(initialValue: item.textContent ?? "")
        _language = State(initialValue: item.language ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                contentPreview
                actionBar
                if editing { editor } else { metadata }
            }
            .padding()
            .frame(maxWidth: 780, alignment: .leading)
        }
        .navigationTitle(item.displayTitle)
        .task { appModel.markUsed(item, metric: .itemOpened) }
        .quickLookPreview($previewURL)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editing ? "Done" : "Edit") {
                    if editing { appModel.save(item, title: title, note: note, text: text, language: language) }
                    editing.toggle()
                }
            }
            ToolbarItem { Button { appModel.togglePin(item) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.fill" : "pin") } }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .link:
            VStack(alignment: .leading, spacing: 16) {
                if let data = item.linkPreviewImageData, let image = platformImage(data: data) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: isCompactLayout ? 180 : 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                HStack(alignment: .top, spacing: 12) {
                    if let data = item.faviconData, let icon = platformImage(data: data) {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    } else {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.sourceDomain ?? item.urlString ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let description = item.displayLinkDescription {
                    Text(description)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            .onDrag { dragProvider() }
        case .text:
            Text(item.textContent ?? "")
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onDrag { dragProvider() }
        case .code:
            ScrollView(.horizontal) {
                Text(SimpleSyntaxHighlighter.highlight(item.textContent ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("syntax-highlighted-code")
            .onDrag { dragProvider() }
        case .image:
            if let attachment = attachments.first, let image = platformImage(data: attachment.data) {
                image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(imageScale)
                    .gesture(MagnifyGesture().onChanged { value in imageScale = min(max(value.magnification, 1), 5) })
                    .accessibilityIdentifier("zoomable-image")
                    .onDrag { dragProvider(attachment) }
            } else { ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark") }
        case .file:
            VStack(spacing: 12) {
                Image(systemName: "doc.fill").font(.system(size: 64)).foregroundStyle(.orange)
                Text(item.fileName ?? item.title).font(.title3)
                if let attachment = attachments.first { Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .onDrag { dragProvider(attachments.first) }
        }
    }

    private var attachments: [StowAttachment] { allAttachments.filter { $0.itemID == item.id } }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
            Group {
                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(metadataEntries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.value)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(metadataEntries) { entry in
                            metadataRow(entry.label, entry.value)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
        .textSelection(.enabled)
    }

    private var metadataEntries: [ItemMetadataEntry] {
        var entries: [ItemMetadataEntry] = []
        if item.type != .link { entries.append(ItemMetadataEntry(label: "Title", value: item.displayTitle)) }
        if let note = item.note, !note.isEmpty { entries.append(ItemMetadataEntry(label: "Note", value: note)) }
        entries.append(ItemMetadataEntry(label: "Added", value: item.createdAt.formatted(date: .abbreviated, time: .shortened)))
        entries.append(ItemMetadataEntry(label: "Last used", value: item.lastUsedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"))
        entries.append(ItemMetadataEntry(label: "Source", value: item.sourceApp ?? "Unknown"))
        if let url = item.urlString { entries.append(ItemMetadataEntry(label: "Original URL", value: url)) }
        if item.type == .code { entries.append(ItemMetadataEntry(label: "Language", value: item.language ?? "Plain text")) }
        return entries
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Note", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            if item.type == .text || item.type == .code {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                if item.type == .code {
                    TextField("Language", text: $language)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)
            if isCompactLayout {
                LazyVGrid(columns: compactActionColumns, spacing: 10) {
                    actionButtons(fillsWidth: true)
                }
            } else {
                HStack(spacing: 10) {
                    actionButtons(fillsWidth: false)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private func actionButtons(fillsWidth: Bool) -> some View {
        Button {
            let representations = appModel.representations(for: item)
            appModel.performUse(item, action: .copy, metric: .itemCopied) {
                try PlatformActions.copy(
                    item,
                    attachmentData: attachments.first?.data,
                    attachment: attachments.first,
                    representations: representations
                )
            }
        } label: {
            actionLabel("Copy", systemImage: "doc.on.doc", fillsWidth: fillsWidth)
        }
        .buttonStyle(.borderedProminent)
        if item.type == .link || item.type == .file {
            Button {
                appModel.performUse(item, action: .open, metric: .itemOpened) {
                    try PlatformActions.open(item, attachment: attachments.first)
                }
            } label: {
                actionLabel(item.type == .link ? "Open Link" : "Open In", systemImage: "arrow.up.forward.app", fillsWidth: fillsWidth)
            }
        }
        if item.type == .file, let attachment = attachments.first {
            Button {
                appModel.performUse(item, action: .preview, metric: .itemOpened) {
                    previewURL = try PlatformActions.materialize(attachment)
                }
            } label: {
                actionLabel("Quick Look", systemImage: "eye", fillsWidth: fillsWidth)
            }
        }
        StowShareButton(item: item, attachment: attachments.first, fillsWidth: fillsWidth)
        #if os(iOS)
        if item.type == .image, let data = attachments.first?.data {
            Button {
                appModel.performUse(item, action: .open, metric: .itemOpened) {
                    try PlatformActions.saveToPhotos(data)
                }
            } label: {
                actionLabel("Save Image", systemImage: "photo.badge.arrow.down", fillsWidth: fillsWidth)
            }
        }
        #endif
        Button { appModel.archiveOrRestore(item) } label: {
            actionLabel(item.status == .archived ? "Restore" : "Archive", systemImage: "archivebox", fillsWidth: fillsWidth)
        }
        Button(role: .destructive) { appModel.trashOrRestore(item) } label: {
            actionLabel(item.status == .trashed ? "Restore" : "Delete", systemImage: item.status == .trashed ? "arrow.uturn.backward" : "trash", fillsWidth: fillsWidth)
        }
    }

    private func actionLabel(_ title: String, systemImage: String, fillsWidth: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 22)
    }

    private var compactActionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var isCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func dragProvider(_ attachment: StowAttachment? = nil) -> NSItemProvider {
        let success = DragSuccessToken { appModel.markUsed(item, metric: .itemDragged) }
        let provider = NSItemProvider()
        let payload = DragPayload(item: item, attachment: attachment)
        provider.suggestedName = payload.suggestedName
        provider.registerDataRepresentation(forTypeIdentifier: payload.typeIdentifier, visibility: .all) { completion in
            completion(payload.data, nil)
            success.record()
            return nil
        }
        return provider
    }

    private func platformImage(data: Data) -> Image? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #endif
    }
}

private struct ItemMetadataEntry: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

extension StowItem {
    var displayTitle: String {
        type == .link ? HTMLMetadataParser.decodeCharacterReferences(title) : title
    }

    var displayLinkDescription: String? {
        linkDescription.map(HTMLMetadataParser.decodeCharacterReferences)
    }
}

private final class DragSuccessToken: @unchecked Sendable {
    private let success: @MainActor () -> Void

    init(success: @escaping @MainActor () -> Void) { self.success = success }

    nonisolated func record() {
        Task { @MainActor in success() }
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

    private static func apply(_ pattern: String, color: Color, bold: Bool = false, source: String, result: inout AttributedString) {
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
