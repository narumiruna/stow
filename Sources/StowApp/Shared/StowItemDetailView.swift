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
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note ?? "")
        _text = State(initialValue: item.textContent ?? "")
        _language = State(initialValue: item.language ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                contentPreview
                Divider()
                if editing { editor } else { metadata }
                actionBar
            }
            .padding()
            .frame(maxWidth: 780, alignment: .leading)
        }
        .navigationTitle(item.title)
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
            VStack(alignment: .leading, spacing: 12) {
                if let data = item.linkPreviewImageData, let image = platformImage(data: data) {
                    image.resizable().scaledToFill().frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack(spacing: 10) {
                    if let data = item.faviconData, let icon = platformImage(data: data) {
                        icon.resizable().scaledToFit().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "link.circle.fill").font(.system(size: 36)).foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading) {
                        Text(item.title).font(.title2.bold())
                        Text(item.sourceDomain ?? item.urlString ?? "").foregroundStyle(.secondary)
                    }
                }
                if let description = item.linkDescription { Text(description).foregroundStyle(.secondary) }
                if let url = item.urlString { Text(url).font(.callout).textSelection(.enabled) }
            }
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
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            metadataRow("Title", item.title)
            if let note = item.note, !note.isEmpty { metadataRow("Note", note) }
            metadataRow("Added", item.createdAt.formatted(date: .abbreviated, time: .shortened))
            metadataRow("Last used", item.lastUsedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            metadataRow("Source", item.sourceApp ?? "Unknown")
            if let url = item.urlString { metadataRow("Original URL", url) }
            if item.type == .code { metadataRow("Language", item.language ?? "Plain text") }
        }
        .textSelection(.enabled)
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
        HStack(spacing: 12) {
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
            } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(.borderedProminent)
            if item.type == .link || item.type == .file {
                Button { appModel.performUse(item, action: .open, metric: .itemOpened) { try PlatformActions.open(item, attachment: attachments.first) } } label: { Label(item.type == .link ? "Open Link" : "Open In", systemImage: "arrow.up.forward.app") }
            }
            if item.type == .file, let attachment = attachments.first {
                Button {
                    appModel.performUse(item, action: .preview, metric: .itemOpened) { previewURL = try PlatformActions.materialize(attachment) }
                } label: { Label("Quick Look", systemImage: "eye") }
            }
            StowShareButton(item: item, attachment: attachments.first)
            #if os(iOS)
            if item.type == .image, let data = attachments.first?.data {
                Button { appModel.performUse(item, action: .open, metric: .itemOpened) { try PlatformActions.saveToPhotos(data) } } label: { Label("Save Image", systemImage: "photo.badge.arrow.down") }
            }
            #endif
            Button { appModel.archiveOrRestore(item) } label: { Label(item.status == .archived ? "Restore" : "Archive", systemImage: "archivebox") }
            Button(role: .destructive) { appModel.trashOrRestore(item) } label: { Label(item.status == .trashed ? "Restore" : "Delete", systemImage: item.status == .trashed ? "arrow.uturn.backward" : "trash") }
        }
        .controlSize(.large)
        .fixedSize(horizontal: false, vertical: true)
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
