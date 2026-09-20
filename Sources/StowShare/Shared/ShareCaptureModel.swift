@preconcurrency import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
import StowCore

private struct LoadedShareFile: Sendable {
    let fileURL: URL
    let stagingDirectoryURL: URL
    let byteCount: Int
    let contentType: UTType?
}

@MainActor
@Observable
final class ShareCaptureModel {
    typealias StorageRoot = @MainActor () throws -> URL
    typealias SpoolFactory = @MainActor (URL) throws -> CaptureSpool
    typealias FileCopy = @Sendable (URL, URL) throws -> Void

    var title = ""
    var note = ""
    var isPinned = false
    var saveAsCode = false
    var directlyArchive = false
    var language = ""
    var preview = "Loading shared content…"
    var isLoading = true
    var isSaving = false
    private(set) var loadErrorMessage: String?
    private(set) var saveErrorMessage: String?
    var previewImageData: Data?

    var errorMessage: String? { loadErrorMessage ?? saveErrorMessage }
    var canSaveAsCode: Bool { draft?.type == .text }
    var canSave: Bool { draft != nil && loadErrorMessage == nil && !isLoading && !isSaving }

    private let storageRoot: StorageRoot
    private let spoolFactory: SpoolFactory
    private let stagingRootURL: URL
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let copyFile: FileCopy
    private var draft: CaptureDraft?
    private var stagedAttachmentURL: URL?
    private var stagingDirectoryURL: URL?
    private var loadGeneration = 0

    init(
        storageRoot: @escaping StorageRoot = { try ShareCaptureModel.defaultStorageRoot() },
        spoolFactory: @escaping SpoolFactory = { try CaptureSpool(rootURL: $0) },
        stagingRootURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("StowShareImports", isDirectory: true),
        fileManager: FileManager = .default,
        copyFile: @escaping FileCopy = { try FileManager.default.copyItem(at: $0, to: $1) }
    ) {
        self.storageRoot = storageRoot
        self.spoolFactory = spoolFactory
        self.stagingRootURL = stagingRootURL
        self.fileManager = fileManager
        self.copyFile = copyFile
    }

    func load(from extensionItems: [NSExtensionItem]) async {
        loadGeneration += 1
        let generation = loadGeneration
        cleanupStaging()
        draft = nil
        loadErrorMessage = nil
        saveErrorMessage = nil
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            guard let providers = extensionItems.first?.attachments, !providers.isEmpty else {
                throw CaptureValidationError.missingText
            }
            let descriptors = providers.map {
                CaptureProviderDescriptor(
                    typeIdentifiers: $0.registeredTypeIdentifiers,
                    suggestedName: $0.suggestedName
                )
            }
            guard let selection = CaptureRepresentationSelector.select(descriptors) else {
                throw CaptureValidationError.unsupportedRepresentation
            }
            let provider = providers[selection.providerIndex]
            switch selection.kind {
            case .url:
                guard let url = try await loadURL(provider) else {
                    throw CaptureValidationError.invalidURL
                }
                guard isCurrentLoad(generation) else { return }
                draft = CaptureDraft(type: .link, title: provider.suggestedName ?? "", urlString: url.absoluteString)
                preview = url.absoluteString
                title = provider.suggestedName ?? ""
            case .text:
                guard let text = try await loadText(provider) else {
                    throw CaptureValidationError.missingText
                }
                guard isCurrentLoad(generation) else { return }
                draft = CaptureDraft(type: .text, title: "", textContent: text)
                preview = text
            case .image, .file:
                let expectedType = selection.kind == .image ? UTType.image : UTType.data
                guard let identifier = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: expectedType) == true
                }), let loadedFile = try await loadFile(provider, typeIdentifier: identifier) else {
                    throw CaptureValidationError.missingAttachment
                }
                guard isCurrentLoad(generation) else {
                    try? fileManager.removeItem(at: loadedFile.stagingDirectoryURL)
                    return
                }
                stagedAttachmentURL = loadedFile.fileURL
                stagingDirectoryURL = loadedFile.stagingDirectoryURL
                let contentType = loadedFile.contentType ?? UTType(identifier)
                let inferredType: ItemType = selection.kind == .image || contentType?.conforms(to: .image) == true ? .image : .file
                if inferredType == .image { previewImageData = imagePreviewData(at: loadedFile.fileURL) }
                let fallbackName = inferredType == .image ? "Image" : loadedFile.fileURL.lastPathComponent
                draft = CaptureDraft(
                    type: inferredType,
                    title: provider.suggestedName ?? fallbackName,
                    stagedAttachmentName: loadedFile.fileURL.lastPathComponent,
                    attachmentByteCount: loadedFile.byteCount,
                    contentType: contentType?.identifier,
                    fileName: provider.suggestedName ?? loadedFile.fileURL.lastPathComponent
                )
                preview = provider.suggestedName ?? fallbackName
                title = provider.suggestedName ?? fallbackName
            }
        } catch {
            guard isCurrentLoad(generation) else { return }
            cleanupStaging()
            loadErrorMessage = error.localizedDescription
        }
    }

    func save() throws {
        guard var draft else { throw CaptureValidationError.missingText }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            draft.title = title
            draft.note = note
            draft.isPinned = isPinned
            draft.directlyArchive = directlyArchive
            if saveAsCode, draft.type == .text {
                draft.type = .code
                draft.language = language
            }
            let root = try storageRoot()
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let spool = try spoolFactory(root.appendingPathComponent("CaptureSpool", isDirectory: true))
            try spool.stage(draft, attachmentURL: stagedAttachmentURL)
            cleanupStaging()
        } catch {
            saveErrorMessage = error.localizedDescription
            throw error
        }
    }

    func cancel() {
        loadGeneration += 1
        isLoading = false
        isSaving = false
        draft = nil
        cleanupStaging()
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    private func cleanupStaging() {
        if let stagingDirectoryURL {
            try? fileManager.removeItem(at: stagingDirectoryURL)
        }
        stagingDirectoryURL = nil
        stagedAttachmentURL = nil
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let url = item as? URL { continuation.resume(returning: url); return }
                if let string = item as? String { continuation.resume(returning: URL(string: string)); return }
                if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: URL(string: string)); return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error); return }
                if let string = item as? String { continuation.resume(returning: string); return }
                if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8)); return
                }
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
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func loadFile(_ provider: NSItemProvider, typeIdentifier: String) async throws -> LoadedShareFile? {
        let stagingRootURL = stagingRootURL
        let copyFile = copyFile
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sourceURL else { continuation.resume(returning: nil); return }
                var directory: URL?
                do {
                    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                    let byteCount = values.fileSize ?? 0
                    guard byteCount <= 100 * 1_024 * 1_024 else {
                        throw CaptureValidationError.attachmentTooLarge
                    }
                    let createdDirectory = stagingRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    directory = createdDirectory
                    try FileManager.default.createDirectory(at: createdDirectory, withIntermediateDirectories: true)
                    let destination = createdDirectory.appendingPathComponent(sourceURL.lastPathComponent)
                    try copyFile(sourceURL, destination)
                    continuation.resume(returning: LoadedShareFile(
                        fileURL: destination,
                        stagingDirectoryURL: createdDirectory,
                        byteCount: byteCount,
                        contentType: values.contentType
                    ))
                } catch {
                    if let directory { try? FileManager.default.removeItem(at: directory) }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func defaultStorageRoot() throws -> URL {
        #if targetEnvironment(simulator)
        return StowSharedStorage.simulatorContainerURL(
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"]
        )
        #else
        #if DEBUG && os(macOS)
        let fallback = StowSharedStorage.developmentFallbackContainerURL()
        #else
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowShared", isDirectory: true)
        #endif
        return StowSharedStorage.sharedContainerURL(
            appGroupContainerURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: StowSharedStorage.appGroupIdentifier
            ),
            fallbackURL: fallback
        )
        #endif
    }
}
