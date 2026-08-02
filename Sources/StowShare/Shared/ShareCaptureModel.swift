@preconcurrency import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
import StowCore

@MainActor
@Observable
final class ShareCaptureModel {
    var title = ""
    var note = ""
    var isPinned = false
    var saveAsCode = false
    var directlyArchive = false
    var language = ""
    var preview = "Loading shared content…"
    var isLoading = true
    var isSaving = false
    var errorMessage: String?
    var previewImageData: Data?

    private var draft: CaptureDraft?
    private var stagedAttachmentURL: URL?
    var canSaveAsCode: Bool { draft?.type == .text }

    func load(from extensionItems: [NSExtensionItem]) async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let providers = extensionItems.first?.attachments, !providers.isEmpty else {
                throw CaptureValidationError.missingText
            }
            let descriptors = providers.map { CaptureProviderDescriptor(typeIdentifiers: $0.registeredTypeIdentifiers, suggestedName: $0.suggestedName) }
            guard let selection = CaptureRepresentationSelector.select(descriptors) else { throw CaptureValidationError.unsupportedRepresentation }
            let provider = providers[selection.providerIndex]
            switch selection.kind {
            case .url:
                guard let url = try await loadURL(provider) else { throw CaptureValidationError.invalidURL }
                draft = CaptureDraft(type: .link, title: provider.suggestedName ?? "", urlString: url.absoluteString)
                preview = url.absoluteString
                title = provider.suggestedName ?? ""
            case .text:
                guard let text = try await loadText(provider) else { throw CaptureValidationError.missingText }
                draft = CaptureDraft(type: .text, title: "", textContent: text)
                preview = text
            case .image, .file:
                let expectedType = selection.kind == .image ? UTType.image : UTType.data
                guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: expectedType) == true }),
                      let file = try await loadFile(provider, typeIdentifier: identifier) else { throw CaptureValidationError.missingAttachment }
                stagedAttachmentURL = file
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                let contentType = values.contentType ?? UTType(identifier)
                guard (values.fileSize ?? 0) <= 100 * 1_024 * 1_024 else { throw CaptureValidationError.attachmentTooLarge }
                let inferredType: ItemType = selection.kind == .image || contentType?.conforms(to: .image) == true ? .image : .file
                if inferredType == .image { previewImageData = imagePreviewData(at: file) }
                let fallbackName = inferredType == .image ? "Image" : file.lastPathComponent
                draft = CaptureDraft(type: inferredType, title: provider.suggestedName ?? fallbackName, stagedAttachmentName: file.lastPathComponent, attachmentByteCount: values.fileSize, contentType: contentType?.identifier, fileName: provider.suggestedName ?? file.lastPathComponent)
                preview = provider.suggestedName ?? fallbackName
                title = provider.suggestedName ?? fallbackName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() throws {
        guard var draft else { throw CaptureValidationError.missingText }
        isSaving = true
        defer { isSaving = false }
        draft.title = title
        draft.note = note
        draft.isPinned = isPinned
        draft.directlyArchive = directlyArchive
        if saveAsCode, draft.type == .text {
            draft.type = .code
            draft.language = language
        }
        let root: URL
        #if targetEnvironment(simulator)
        let simulatorID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        root = URL(fileURLWithPath: "/tmp/StowSimulatorAppGroup/\(simulatorID)", isDirectory: true)
        #else
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.narumi.stow") {
            root = groupURL
        } else {
            #if DEBUG && os(macOS)
            root = FileManager.default.temporaryDirectory.appendingPathComponent("StowDevelopmentAppGroup", isDirectory: true)
            #else
            root = FileManager.default.temporaryDirectory.appendingPathComponent("StowShared", isDirectory: true)
            #endif
        }
        #endif
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let spool = try CaptureSpool(rootURL: root.appendingPathComponent("CaptureSpool", isDirectory: true))
        try spool.stage(draft, attachmentURL: stagedAttachmentURL)
        if let stagedAttachmentURL { try? FileManager.default.removeItem(at: stagedAttachmentURL.deletingLastPathComponent()) }
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let url = item as? URL { continuation.resume(returning: url); return }
                if let string = item as? String { continuation.resume(returning: URL(string: string)); return }
                if let data = item as? Data, let string = String(data: data, encoding: .utf8) { continuation.resume(returning: URL(string: string)); return }
                continuation.resume(returning: nil)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let string = item as? String { continuation.resume(returning: string); return }
                if let data = item as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)); return }
                continuation.resume(returning: nil)
            }
        }
    }

    private func imagePreviewData(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func loadFile(_ provider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sourceURL else { continuation.resume(returning: nil); return }
                do {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StowShareImports/\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    continuation.resume(returning: destination)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
