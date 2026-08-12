import Foundation
import StowCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PlatformActionError: LocalizedError, Equatable {
    case unavailable
    var errorDescription: String? { "This item is not available for that action." }
}

#if os(macOS)
@MainActor
protocol PlatformPasteboardWriting {
    func write(_ payload: PastePayload) -> Bool
}

@MainActor
final class SystemPlatformPasteboardWriter: PlatformPasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ payload: PastePayload) -> Bool {
        guard !payload.entries.isEmpty else { return false }
        let item = NSPasteboardItem()
        for entry in payload.entries {
            let type = NSPasteboard.PasteboardType(entry.typeIdentifier)
            if let string = String(data: entry.data, encoding: .utf8),
               entry.typeIdentifier == StowRepresentationType.plainText
                || entry.typeIdentifier == StowRepresentationType.url
                || entry.typeIdentifier == StowRepresentationType.fileURL
                || entry.typeIdentifier == StowRepresentationType.stowOwned {
                item.setString(string, forType: type)
            } else {
                item.setData(entry.data, forType: type)
            }
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
#endif

@MainActor
enum PlatformActions {
    static func copy(
        _ item: StowItem,
        attachmentData: Data? = nil,
        attachment: StowAttachment? = nil,
        representations: [StowRepresentation] = [],
        format: PasteFormat = .original
    ) throws {
        #if os(iOS)
        if item.type == .image {
            guard let data = attachmentData ?? attachment?.data, let image = UIImage(data: data) else { throw PlatformActionError.unavailable }
            UIPasteboard.general.image = image
        } else if item.type == .file, let attachment {
            UIPasteboard.general.url = try materialize(attachment)
        } else {
            UIPasteboard.general.string = stringValue(item)
        }
        #elseif os(macOS)
        try copy(
            item,
            attachment: attachment ?? attachmentData.map {
                StowAttachment(
                    itemID: item.id,
                    data: $0,
                    contentType: item.type == .image ? "public.tiff" : "application/octet-stream",
                    fileName: item.fileName ?? item.title
                )
            },
            representations: representations,
            format: format,
            writer: SystemPlatformPasteboardWriter()
        )
        #endif
    }

    #if os(macOS)
    static func copy(
        _ item: StowItem,
        attachment: StowAttachment?,
        representations: [StowRepresentation],
        format: PasteFormat,
        writer: any PlatformPasteboardWriting
    ) throws {
        if item.type == .file {
            guard let attachment else { throw PlatformActionError.unavailable }
            let url = try materialize(attachment)
            let payload = PastePayload(entries: [
                PastePayloadEntry(
                    typeIdentifier: StowRepresentationType.fileURL,
                    data: Data(url.absoluteString.utf8)
                ),
                PastePayloadEntry(
                    typeIdentifier: StowRepresentationType.stowOwned,
                    data: Data("1".utf8)
                ),
            ])
            guard writer.write(payload) else { throw PlatformActionError.unavailable }
            return
        }
        let payload = try PastePayloadBuilder.build(
            item: item,
            attachment: attachment,
            representations: representations,
            format: format
        )
        guard !payload.entries.isEmpty else { throw PlatformActionError.unavailable }
        guard writer.write(payload) else { throw PlatformActionError.unavailable }
    }
    #endif

    static func open(_ item: StowItem, attachment: StowAttachment? = nil) throws {
        let url: URL?
        if item.type == .link {
            url = item.urlString.flatMap(URL.init(string:))
        } else if let attachment {
            url = try? materialize(attachment)
        } else {
            url = nil
        }
        guard let url else { throw PlatformActionError.unavailable }
        #if os(iOS)
        guard UIApplication.shared.canOpenURL(url) else { throw PlatformActionError.unavailable }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        guard NSWorkspace.shared.open(url) else { throw PlatformActionError.unavailable }
        #endif
    }

    #if os(iOS)
    static func saveToPhotos(_ data: Data) throws {
        guard let image = UIImage(data: data) else { throw PlatformActionError.unavailable }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    #endif

    private static func stringValue(_ item: StowItem) -> String {
        (item.type == .link ? item.urlString : item.textContent) ?? item.title
    }

    static func materialize(_ attachment: StowAttachment) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StowOpen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(URL(fileURLWithPath: attachment.fileName).lastPathComponent)
        try attachment.data.write(to: url, options: .atomic)
        return url
    }
}
