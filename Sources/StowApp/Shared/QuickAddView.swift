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
    private let onFinished: (() -> Void)?
    @State private var content = ""
    @State private var title = ""
    @State private var note = ""
    @State private var saveAsCode = false
    @State private var language = ""
    @State private var isPinned = false
    @State private var directlyArchive = false
    @State private var attachmentURL: URL?
    @State private var dropTargeted = false

    init(onFinished: (() -> Void)? = nil) {
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    if let attachmentURL {
                        Label(attachmentURL.lastPathComponent, systemImage: attachmentType(for: attachmentURL) == .image ? "photo" : "doc")
                        Button("Remove Attachment", role: .destructive) { removeAttachment() }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: finish) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(attachmentURL == nil && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("save-item")
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        .onDisappear { removeAttachment() }
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
        let saved: Bool
        if let attachmentURL {
            let values = try? attachmentURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let type = attachmentType(for: attachmentURL)
            saved = appModel.createAttachment(CaptureDraft(
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
            saved = appModel.create(CaptureDraft(
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
        if saved { finish() }
    }

    private func finish() {
        appModel.isAdding = false
        removeAttachment()
        if let onFinished { onFinished() }
        else { dismiss() }
    }

    private func removeAttachment() {
        guard let attachmentURL else { return }
        self.attachmentURL = nil
        removeOwnedStagingDirectory(for: attachmentURL)
    }

    private func removeOwnedStagingDirectory(for url: URL) {
        let importsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowImports", isDirectory: true)
            .standardizedFileURL
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.path.hasPrefix(importsRoot.path + "/") else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    private func attachmentType(for url: URL) -> ItemType {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? .image : .file
    }

    private func adoptFile(_ source: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StowImports/\(UUID().uuidString)", isDirectory: true)
        do {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            let previous = attachmentURL
            attachmentURL = destination
            if let previous { removeOwnedStagingDirectory(for: previous) }
            if title.isEmpty { title = source.deletingPathExtension().lastPathComponent }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            appModel.presentedError = error.localizedDescription
        }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StowImports/\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Pasted Image.\(fileExtension)")
            try data.write(to: url, options: .atomic)
            let previous = attachmentURL
            attachmentURL = url
            if let previous { removeOwnedStagingDirectory(for: previous) }
            if title.isEmpty { title = "Pasted Image" }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            appModel.presentedError = error.localizedDescription
        }
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
