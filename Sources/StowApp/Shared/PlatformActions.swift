import Foundation
import StowCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PlatformActionError: LocalizedError {
    case unavailable
    var errorDescription: String? { "This item is not available for that action." }
}

@MainActor
enum PlatformActions {
    static func copy(_ item: StowItem, attachmentData: Data? = nil) throws {
        #if os(iOS)
        if item.type == .image {
            guard let attachmentData, let image = UIImage(data: attachmentData) else { throw PlatformActionError.unavailable }
            UIPasteboard.general.image = image
        } else {
            UIPasteboard.general.string = stringValue(item)
        }
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.type == .image {
            guard let attachmentData, let image = NSImage(data: attachmentData) else { throw PlatformActionError.unavailable }
            let marker = NSPasteboardItem()
            marker.setString("1", forType: .stowOwnedContent)
            guard pasteboard.writeObjects([image, marker]) else { throw PlatformActionError.unavailable }
        } else {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(stringValue(item), forType: .string)
            pasteboardItem.setString("1", forType: .stowOwnedContent)
            guard pasteboard.writeObjects([pasteboardItem]) else { throw PlatformActionError.unavailable }
        }
        #endif
    }

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
