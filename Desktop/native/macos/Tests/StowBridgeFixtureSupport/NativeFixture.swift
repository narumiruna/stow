import Darwin
import Foundation
import StowCore
import StowDesktopBridge
import SwiftData

/// Native disk fixtures for the headless cross-process verification harness only.
@MainActor
public enum NativeFixture {
    public static let types: [ItemType] = [.link, .text, .code, .image, .file]
    public static let date = Date(timeIntervalSinceReferenceDate: 800_000_000.1234567)

    public static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
    }

    public static func item(_ index: Int) -> StowItem {
        let type = types[index]
        let item = StowItem(
            id: id(index), captureID: UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", index + 1))!,
            type: type, title: "Fixture " + type.rawValue,
            textContent: type == .text || type == .code ? "  Café é\n日本語\n " : nil,
            urlString: type == .link ? "https://example.com/fixture?q=1" : nil,
            fileName: type == .file || type == .image ? "fixture.bin" : nil,
            sourceApp: "Bridge fixture", sourceDomain: type == .link ? "example.com" : nil,
            note: "Native fixture note", language: type == .code ? "swift" : nil,
            createdAt: date, updatedAt: date, lastUsedAt: date.addingTimeInterval(-1),
            lastCapturedAt: date.addingTimeInterval(-2), useCount: index + 2,
            contentFingerprint: "v1:native-preserved-\(index)", status: index == 4 ? .trashed : .archived, isPinned: true,
            trashedAt: index == 4 ? date : nil, statusBeforeTrash: index == 4 ? .archived : nil
        )
        item.linkDescription = "Native description \(index)"
        item.faviconData = Data([0, 1, UInt8(index), 255])
        item.linkPreviewImageData = Data([9, 8, UInt8(index), 0])
        return item
    }

    public static func seed(_ container: ModelContainer) throws {
        let context = container.mainContext
        context.autosaveEnabled = false
        guard try context.fetchCount(FetchDescriptor<StowItem>()) == 0 else { throw FixtureError.invalid }
        for index in types.indices {
            let item = item(index)
            context.insert(item)
            context.insert(StowAttachment(id: attachmentID(index), itemID: item.id,
                                           data: attachmentBytes(index), thumbnailData: Data([7, 0, 9]),
                                           contentType: "application/octet-stream", fileName: "fixture-\(index).bin",
                                           pixelWidth: 12, pixelHeight: 34, createdAt: date))
            context.insert(StowRepresentation(id: representationID(index), itemID: item.id,
                                               typeIdentifier: StowRepresentationType.html,
                                               data: representationBytes(index), ordinal: 3, createdAt: date))
        }
        try context.save()
    }

    public static func verify(_ container: ModelContainer, edited: Bool = true) throws {
        let repository = StowRepository(modelContext: container.mainContext)
        let fixtures = try repository.allItems().filter { $0.sourceApp == "Bridge fixture" }
        guard fixtures.count == types.count else { throw FixtureError.invalid }
        for index in types.indices {
            guard let actual = try repository.item(id: id(index)) else { throw FixtureError.invalid }
            let expected = item(index)
            if edited {
                expected.title = "Edited fixture " + expected.type.rawValue
                expected.note = "Edited fixture note"
                guard actual.updatedAt > date else { throw FixtureError.invalid }
            } else {
                guard actual.updatedAt == date else { throw FixtureError.invalid }
            }
            guard scalarFields(actual) == scalarFields(expected) else { throw FixtureError.invalid }
            let attachments = try repository.attachments(itemID: actual.id)
            guard attachments.count == 1, let a = attachments.first,
                  a.id == attachmentID(index), a.data == attachmentBytes(index), a.thumbnailData == Data([7, 0, 9]),
                  a.fileName == "fixture-\(index).bin", a.contentType == "application/octet-stream",
                  a.byteCount == attachmentBytes(index).count, a.pixelWidth == 12, a.pixelHeight == 34, a.createdAt == date else {
                throw FixtureError.invalid
            }
            let representations = try repository.representations(itemID: actual.id)
            guard representations.count == 1, let r = representations.first,
                  r.id == representationID(index), r.data == representationBytes(index), r.byteCount == representationBytes(index).count,
                  r.typeIdentifier == StowRepresentationType.html, r.ordinal == 3, r.createdAt == date else {
                throw FixtureError.invalid
            }
        }
    }

    private static func attachmentID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "20000000-0000-4000-8000-%012d", index + 1))!
    }
    private static func representationID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "30000000-0000-4000-8000-%012d", index + 1))!
    }
    private static func attachmentBytes(_ index: Int) -> Data { Data([0, 255, 3, UInt8(index), 8]) }
    private static func representationBytes(_ index: Int) -> Data { Data("<b>Native \(index) 日本語</b>".utf8) }

    private static func scalarFields(_ i: StowItem) -> BridgeJSON {
        .object([
            "id": .string(i.id.uuidString), "capture_id": .string(i.captureID.uuidString),
            "type": .string(i.type.rawValue), "title": .string(i.title), "text": optional(i.textContent),
            "url": optional(i.urlString), "file": optional(i.fileName), "source_app": optional(i.sourceApp),
            "domain": optional(i.sourceDomain), "note": optional(i.note), "language": optional(i.language),
            "description": optional(i.linkDescription), "created": .string(BridgeDate.string(i.createdAt)),
            "last_used": optional(i.lastUsedAt.map(BridgeDate.string)),
            "last_captured": optional(i.lastCapturedAt.map(BridgeDate.string)),
            "use_count": .integer(Int64(i.useCount)), "fingerprint": optional(i.contentFingerprint),
            "status": .string(i.status.rawValue), "pinned": .bool(i.isPinned),
            "trashed": optional(i.trashedAt.map(BridgeDate.string)), "before_trash": optional(i.statusBeforeTrash?.rawValue),
            "favicon": bytes(i.faviconData), "preview": bytes(i.linkPreviewImageData),
        ])
    }
    private static func optional(_ value: String?) -> BridgeJSON { value.map(BridgeJSON.string) ?? .null }
    private static func bytes(_ value: Data?) -> BridgeJSON {
        value.map { .array($0.map { .integer(Int64($0)) }) } ?? .null
    }
}

public enum FixtureError: Error { case invalid }
