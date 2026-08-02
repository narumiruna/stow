import SwiftUI
import StowCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var content = ""
    @State private var title = ""
    @State private var note = ""
    @State private var saveAsCode = false
    @State private var language = ""
    @State private var isPinned = false
    @State private var directlyArchive = false
    @State private var attachmentURL: URL?
    @State private var dropTargeted = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    if let attachmentURL {
                        Label(attachmentURL.lastPathComponent, systemImage: attachmentType(for: attachmentURL) == .image ? "photo" : "doc")
                        Button("Remove Attachment", role: .destructive) { self.attachmentURL = nil }
                    } else {
                        TextEditor(text: $content)
                            .frame(minHeight: 160)
                            .accessibilityLabel("Content")
                        Toggle("Save as Code", isOn: $saveAsCode)
                        if saveAsCode { TextField("Language (optional)", text: $language).textInputAutocapitalizationNeverIfAvailable() }
                    }
                    Button { pasteClipboard() } label: { Label("Paste from Clipboard", systemImage: "doc.on.clipboard") }
                    dropZone
                }
                Section("Details") {
                    TextField("Title (optional)", text: $title)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }
                Section("Advanced") {
                    Toggle("Pin", isOn: $isPinned)
                    Toggle("Directly Archive", isOn: $directlyArchive)
                }
            }
            .navigationTitle("Quick Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { appModel.isAdding = false; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(attachmentURL == nil && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("save-item")
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var dropZone: some View {
        Label("Drop an image or file here", systemImage: "arrow.down.doc")
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(dropTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                if url.isFileURL { adoptFile(url) } else { content = url.absoluteString }
                return true
            } isTargeted: { dropTargeted = $0 }
    }

    private func save() {
        if let attachmentURL {
            let values = try? attachmentURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let type = attachmentType(for: attachmentURL)
            appModel.createAttachment(CaptureDraft(
                type: type,
                title: title.isEmpty ? attachmentURL.lastPathComponent : title,
                stagedAttachmentName: attachmentURL.lastPathComponent,
                attachmentByteCount: values?.fileSize,
                contentType: values?.contentType?.identifier,
                fileName: attachmentURL.lastPathComponent,
                note: note,
                isPinned: isPinned,
                directlyArchive: directlyArchive
            ), fileURL: attachmentURL)
        } else {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let looksLikeURL = URL(string: trimmed).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false
            appModel.create(CaptureDraft(
                type: saveAsCode ? .code : (looksLikeURL ? .link : .text),
                title: title,
                textContent: looksLikeURL ? nil : content,
                urlString: looksLikeURL ? trimmed : nil,
                note: note,
                language: language,
                isPinned: isPinned,
                directlyArchive: directlyArchive
            ))
        }
    }

    private func attachmentType(for url: URL) -> ItemType {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? .image : .file
    }

    private func adoptFile(_ source: URL) {
        do {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StowImports/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            attachmentURL = destination
            if title.isEmpty { title = source.deletingPathExtension().lastPathComponent }
        } catch { appModel.presentedError = error.localizedDescription }
    }

    private func pasteClipboard() {
        #if os(macOS)
        if let url = NSPasteboard.general.readObjects(forClasses: [NSURL.self])?.first as? URL, url.isFileURL { adoptFile(url); return }
        if let image = NSImage(pasteboard: NSPasteboard.general), let data = image.tiffRepresentation { adoptData(data, extension: "tiff"); return }
        if let string = NSPasteboard.general.string(forType: .string) { content = string }
        #elseif os(iOS)
        if let image = UIPasteboard.general.image, let data = image.pngData() { adoptData(data, extension: "png"); return }
        if let string = UIPasteboard.general.string { content = string }
        #endif
    }

    private func adoptData(_ data: Data, extension fileExtension: String) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StowImports/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Pasted Image.\(fileExtension)")
            try data.write(to: url, options: .atomic)
            attachmentURL = url
            if title.isEmpty { title = "Pasted Image" }
        } catch { appModel.presentedError = error.localizedDescription }
    }
}

private extension View {
    @ViewBuilder func textInputAutocapitalizationNeverIfAvailable() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
