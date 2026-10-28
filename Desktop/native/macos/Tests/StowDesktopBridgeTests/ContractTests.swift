import Foundation
import StowBridgeFixtureSupport
import StowCore
import SwiftData
import Testing
@testable import StowDesktopBridge

@Suite @MainActor
struct ContractTests {
    @Test func allFiveTypesReopenMetadataPreservesNativeFieldsAndBytes() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        do {
            let owner = try StoreOwner(path: root.path)
            try NativeFixture.seed(owner.container)
            owner.close()
        }
        do {
            let owner = try StoreOwner(path: root.path)
            try NativeFixture.verify(owner.container, edited: false)
            for index in NativeFixture.types.indices {
                let item = try #require(try owner.repository.item(id: NativeFixture.id(index)))
                let payload: BridgeJSON = .object([
                    "id": .string(item.id.uuidString), "expected_updated_at": .string(BridgeDate.string(item.updatedAt)),
                    "edit": .object(["title": .string("Edited fixture " + item.type.rawValue),
                                     "note": .string("Edited fixture note"),
                                     "text_content": item.textContent.map(BridgeJSON.string) ?? .null,
                                     "language": item.language.map(BridgeJSON.string) ?? .null]),
                ])
                let result = try await owner.execute(BridgeRequest(request("update", payload)))
                #expect(result["item"]?["favicon_data"] == .null)
                #expect(result["item"]?["link_preview_image_data"] == .null)
                #expect(result["representations_count"] == .integer(1))
            }
            owner.close()
        }
        let reopened = try StoreOwner(path: root.path)
        try NativeFixture.verify(reopened.container)
        reopened.close()
    }

    @Test func failedEditAndUnsupportedURLDoNotMutate() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let owner = try StoreOwner(path: root.path)
        let item = try owner.repository.create(from: CaptureDraft(type: .text, title: "Original", textContent: "body"),
                                               representations: [StowRepresentationDraft(typeIdentifier: StowRepresentationType.html,
                                                                                       data: Data("<b>body</b>".utf8), ordinal: 0)])
        let before = try owner.detail(item)
        let edit = request("update", .object([
            "id": .string(item.id.uuidString), "expected_updated_at": .string(BridgeDate.string(item.updatedAt)),
            "edit": .object(["title": .string("Must not change"), "text_content": .string(" \n ")]),
        ]))
        do { _ = try await owner.execute(BridgeRequest(edit)); Issue.record("accepted empty text") }
        catch { #expect((error as? BridgeFailure)?.code == "invalid_argument") }
        #expect(try owner.detail(item) == before)
        #expect(try owner.repository.representations(itemID: item.id).first?.data == Data("<b>body</b>".utf8))
        for url in ["https://example.com/日本語", "https://example.com/a b", "http:///example.com", "https://example.com/%G0", "file:///tmp/secret"] {
            let payload: BridgeJSON = .object(["capture_id": .string(UUID().uuidString), "item_type": .string("link"),
                                               "title": .string(""), "url_string": .string(url)])
            do { _ = try await owner.execute(BridgeRequest(request("create", payload))); Issue.record("accepted unsupported URL") }
            catch { #expect((error as? BridgeFailure)?.code == "invalid_argument") }
        }
        #expect(try owner.repository.allItems().count == 1)
        owner.close()
    }

    @Test func exactSearchBoundsFilterBeforeLimit() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let owner = try StoreOwner(path: root.path)
        let midnight = try #require(try BridgeDate.parse("2026-01-02T00:00:00Z"))
        let before = Date(timeIntervalSinceReferenceDate: midnight.timeIntervalSinceReferenceDate.nextDown)
        let after = Date(timeIntervalSinceReferenceDate: midnight.timeIntervalSinceReferenceDate.nextUp)
        for (title, date) in [("before", before), ("midnight", midnight), ("after", after)] {
            _ = try owner.repository.create(from: CaptureDraft(type: .text, title: title, textContent: "body", isPinned: true), at: date)
        }
        func titles(_ payload: BridgeJSON) async throws -> [String] {
            let result = try await owner.execute(BridgeRequest(request("search", payload)))
            guard case .array(let rows) = result else { throw FixtureError.invalid }
            return rows.compactMap { $0["title"]?.string }
        }
        let upper: BridgeJSON = .object(["added_before": .string("2026-01-01T23:59:59.999999999Z"),
                                         "pinned_only": .bool(true), "limit": .integer(1)])
        #expect(try await titles(upper) == ["before"])
        #expect(try await titles(.object(["added_after": .string("2026-01-02T00:00:00.000000001Z")])) == ["after"])
        #expect(try await titles(.object(["added_after": .string("2026-01-02T00:00:00Z"),
                                         "added_before": .string("2026-01-02T01:00:00+01:00")])) == ["midnight"])
        // Switching back to a prior window must refresh the derived indexes.
        #expect(try await titles(upper) == ["before"])
        #expect(try await titles(.object(["added_after": .string(BridgeDate.string(before)),
                                         "added_before": .string(BridgeDate.string(before))])) == ["before"])
        owner.close()
    }

    @Test func recoveryDoesNotCreateAnEmptyReplacement() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let owner = try StoreOwner(path: root.path)
        _ = try owner.repository.create(from: CaptureDraft(type: .text, title: "Canonical", textContent: "body"))
        // Drop the native resources as on a storage failure, then remove only this disposable root.
        owner.discardFailedStorage()
        try FileManager.default.removeItem(at: root)
        do {
            _ = try await owner.execute(BridgeRequest(request("get", .object(["id": .string(UUID().uuidString)]))))
            Issue.record("missing store recovered as an empty replacement")
        } catch { #expect((error as? BridgeFailure)?.code == "storage") }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        owner.close()
    }

    @Test func sharedBackendFixture() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../fixtures/backend.json").standardizedFileURL
        let fixture = try JSONDecoder().decode(BridgeJSON.self, from: Data(contentsOf: fixtureURL))
        #expect(fixture["version"] == .integer(1))
        guard case .array(let items) = fixture["items"], case .array(let normalization) = fixture["normalization"],
              case .array(let pairs) = fixture["revision_pairs"], case .array(let lifecycle) = fixture["lifecycle"],
              case .array(let errors) = fixture["errors"] else { Issue.record("invalid fixture"); return }
        #expect(items.count == 5)
        for value in items {
            let item = try nativeItem(value)
            #expect(StoreOwner.snapshot(item) == value)
            #expect(try JSONDecoder().decode(BridgeJSON.self, from: JSONEncoder().encode(value)) == value)
        }
        for value in normalization {
            let root = try tempRoot(); defer { cleanup(root) }
            let owner = try StoreOwner(path: root.path)
            let draft = try #require(value["draft"])
            let native = try nativeDraft(draft)
            #expect(((try? native.normalized()) != nil) == (value["swift_ok"] == .bool(true)))
            let payload: BridgeJSON = .object([
                "capture_id": draft["id"]!, "item_type": draft["item_type"]!, "title": draft["title"]!,
                "text_content": draft["text_content"]!, "url_string": draft["url_string"]!,
                "note": draft["note"]!, "language": draft["language"]!, "source_app": draft["source_app"]!,
                "is_pinned": draft["is_pinned"]!, "directly_archive": draft["directly_archive"]!,
            ])
            if value["rust_ok"] == .bool(true) {
                let result = try await owner.execute(BridgeRequest(request("create", payload)))
                guard case .object(let expected) = value["expected"] else { Issue.record("missing expected"); return }
                for (key, expectedValue) in expected { #expect(result["item"]?[key] == expectedValue) }
            } else {
                do { _ = try await owner.execute(BridgeRequest(request("create", payload))); Issue.record("unsupported normalization accepted") }
                catch { #expect((error as? BridgeFailure)?.code == "invalid_argument") }
                #expect(try owner.repository.allItems().isEmpty)
            }
            owner.close()
        }
        for pair in pairs {
            // Emit the native revision, then compare strings; a supplied 1ns drift must conflict.
            let date = try #require(try BridgeDate.parse(pair["first"]?.string))
            let emitted = BridgeJSON.string(BridgeDate.string(date))
            #expect(emitted == pair["first"])
            #expect((emitted == pair["second"]) == (pair["equal"] == .bool(true)))
        }
        for sequence in lifecycle {
            let root = try tempRoot(); defer { cleanup(root) }
            let owner = try StoreOwner(path: root.path)
            let item = try owner.repository.create(from: CaptureDraft(type: .text, title: "fixture", textContent: "body"))
            item.status = try ItemStatus(rawValue: #require(sequence["initial"]?.string))!
            try owner.container.mainContext.save()
            guard case .array(let actions) = sequence["actions"] else { Issue.record("missing actions"); return }
            for action in actions {
                _ = try await owner.execute(BridgeRequest(request("apply", .object([
                    "id": .string(item.id.uuidString), "expected_updated_at": .string(BridgeDate.string(item.updatedAt)), "command": action,
                ]))))
            }
            #expect(item.status.rawValue == sequence["expected"]?.string)
            owner.close()
        }
        for error in errors {
            try error.fields(["code", "message", "retryable"])
            #expect(error["code"]?.string != nil)
            #expect(error["message"]?.string != nil)
            #expect(try JSONDecoder().decode(BridgeJSON.self, from: JSONEncoder().encode(error)) == error)
        }
    }

    private func nativeDraft(_ d: BridgeJSON) throws -> CaptureDraft {
        CaptureDraft(id: try UUID(uuidString: #require(d["id"]?.string))!,
                     type: try ItemType(rawValue: #require(d["item_type"]?.string))!,
                     title: try #require(d["title"]?.string), textContent: d["text_content"]?.string,
                     urlString: d["url_string"]?.string, stagedAttachmentName: d["staged_attachment_name"]?.string,
                     contentType: d["content_type"]?.string, fileName: d["file_name"]?.string,
                     sourceApp: d["source_app"]?.string, sourceDomain: d["source_domain"]?.string,
                     note: d["note"]?.string, language: d["language"]?.string,
                     isPinned: d["is_pinned"] == .bool(true), directlyArchive: d["directly_archive"] == .bool(true))
    }

    private func nativeItem(_ d: BridgeJSON) throws -> StowItem {
        let item = StowItem(
            id: try UUID(uuidString: #require(d["id"]?.string))!,
            captureID: try UUID(uuidString: #require(d["capture_id"]?.string))!,
            type: try ItemType(rawValue: #require(d["item_type"]?.string))!, title: try #require(d["title"]?.string),
            textContent: d["text_content"]?.string, urlString: d["url_string"]?.string, fileName: d["file_name"]?.string,
            sourceApp: d["source_app"]?.string, sourceDomain: d["source_domain"]?.string, note: d["note"]?.string,
            language: d["language"]?.string, createdAt: try #require(try BridgeDate.parse(d["created_at"]?.string)),
            updatedAt: try BridgeDate.parse(d["updated_at"]?.string), lastUsedAt: try BridgeDate.parse(d["last_used_at"]?.string),
            lastCapturedAt: try BridgeDate.parse(d["last_captured_at"]?.string), useCount: try #require(d["use_count"]).decode(Int.self),
            contentFingerprint: d["content_fingerprint"]?.string, status: try ItemStatus(rawValue: #require(d["status"]?.string))!,
            isPinned: d["is_pinned"] == .bool(true), trashedAt: try BridgeDate.parse(d["trashed_at"]?.string),
            statusBeforeTrash: d["status_before_trash"]?.string.flatMap(ItemStatus.init(rawValue:))
        )
        item.linkDescription = d["link_description"]?.string
        return item
    }
}
