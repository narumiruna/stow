import Foundation
import StowCore

private enum StowAutomationHostError: Error {
    case missingPayload
    case itemNotFound
    case attachmentNotFound
    case attachmentSelectionRequired
}

@MainActor
final class StowAutomationHostService {
    private let model: AppModel
    private let spool: StowAutomationSpool
    private let hostVersion: String

    init(model: AppModel, spool: StowAutomationSpool, hostVersion: String? = nil) {
        self.model = model
        self.spool = spool
        self.hostVersion = hostVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }

    func execute(_ request: StowAutomationRequest) async -> StowAutomationResponse {
        guard request.schemaVersion == StowAutomationProtocol.schemaVersion else {
            return failure(
                request,
                code: .unsupportedVersion,
                message: "This request uses an unsupported automation protocol version."
            )
        }
        do {
            let result = try await perform(request)
            return StowAutomationResponse(requestID: request.requestID, data: result)
        } catch let error as StowAutomationError {
            return StowAutomationResponse(requestID: request.requestID, error: error)
        } catch let error as CaptureValidationError {
            return failure(request, code: .validationFailed, message: error.localizedDescription)
        } catch let error as StowAutomationHostError {
            switch error {
            case .missingPayload:
                return failure(request, code: .invalidRequest, message: "The command payload is missing or invalid.")
            case .itemNotFound:
                return failure(request, code: .itemNotFound, message: "The requested item was not found.")
            case .attachmentNotFound:
                return failure(request, code: .attachmentNotFound, message: "The requested attachment was not found.")
            case .attachmentSelectionRequired:
                return failure(request, code: .attachmentSelectionRequired, message: "This item has multiple attachments; specify an attachment ID.")
            }
        } catch let error as SearchIndexError {
            return failure(request, code: .internalFailure, message: error.localizedDescription, retryable: true)
        } catch {
            return failure(request, code: .internalFailure, message: error.localizedDescription)
        }
    }

    private func perform(_ request: StowAutomationRequest) async throws -> StowAutomationResult {
        guard let repository = model.repository else {
            throw StowAutomationError(code: .hostUnavailable, message: "The Stow library is not ready.", retryable: true)
        }
        switch request.command {
        case .status:
            return StowAutomationResult(status: StowAutomationHostStatus(
                hostVersion: hostVersion,
                storage: model.usesPrivateICloud ? "icloud" : "local"
            ))

        case .search:
            guard let payload = request.search else { throw StowAutomationHostError.missingPayload }
            let items = try repository.allItems()
            let ids = try await model.searchForAutomation(items: items, payload: payload)
            let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let attachmentCounts = try attachmentCountsByItem(repository)
            let results = ids.compactMap { itemsByID[$0] }.map {
                summary($0, query: payload.query, attachmentCount: attachmentCounts[$0.id, default: 0])
            }
            return StowAutomationResult(items: results)

        case .get:
            guard let payload = request.get else { throw StowAutomationHostError.missingPayload }
            guard let item = try repository.item(id: payload.itemID) else { throw StowAutomationHostError.itemNotFound }
            return StowAutomationResult(item: try detail(item, repository: repository))

        case .add:
            guard let payload = request.add else { throw StowAutomationHostError.missingPayload }
            var draft = payload.draft
            draft.id = request.requestID
            let item = try model.createForAutomation(draft)
            return StowAutomationResult(item: try detail(item, repository: repository))

        case .export:
            guard let payload = request.export else { throw StowAutomationHostError.missingPayload }
            guard let item = try repository.item(id: payload.itemID) else { throw StowAutomationHostError.itemNotFound }
            let attachments = try repository.attachments(itemID: item.id)
            let attachment: StowAttachment
            if let attachmentID = payload.attachmentID {
                guard let selected = attachments.first(where: { $0.id == attachmentID }) else {
                    throw StowAutomationHostError.attachmentNotFound
                }
                attachment = selected
            } else {
                guard !attachments.isEmpty else { throw StowAutomationHostError.attachmentNotFound }
                guard attachments.count == 1 else { throw StowAutomationHostError.attachmentSelectionRequired }
                attachment = attachments[0]
            }
            let exportURL = try spool.writeExport(attachment.data, fileName: attachment.fileName, requestID: request.requestID)
            try repository.recordSuccessfulUse(item.id)
            return StowAutomationResult(export: StowAutomationExport(
                itemID: item.id,
                attachment: attachmentDTO(attachment),
                path: exportURL.path
            ))
        }
    }

    private func attachmentCountsByItem(_ repository: StowRepository) throws -> [UUID: Int] {
        Dictionary(grouping: try repository.allAttachments(), by: \StowAttachment.itemID).mapValues(\.count)
    }

    private func detail(_ item: StowItem, repository: StowRepository) throws -> StowAutomationItem {
        let attachments = try repository.attachments(itemID: item.id)
            .sorted { $0.createdAt < $1.createdAt }
            .map(attachmentDTO)
        return StowAutomationItem(
            id: item.id,
            captureID: item.captureID,
            type: item.type,
            title: item.title,
            textContent: item.textContent,
            urlString: item.urlString,
            fileName: item.fileName,
            sourceApp: item.sourceApp,
            sourceDomain: item.sourceDomain,
            note: item.note,
            language: item.language,
            linkDescription: item.linkDescription,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            lastUsedAt: item.lastUsedAt,
            useCount: item.useCount,
            status: item.status,
            isPinned: item.isPinned,
            attachments: attachments
        )
    }

    private func summary(_ item: StowItem, query: String?, attachmentCount: Int) -> StowAutomationItemSummary {
        StowAutomationItemSummary(
            id: item.id,
            type: item.type,
            title: item.title,
            snippet: snippet(for: item, query: query),
            sourceApp: item.sourceApp,
            sourceDomain: item.sourceDomain,
            status: item.status,
            isPinned: item.isPinned,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            attachmentCount: attachmentCount
        )
    }

    private func attachmentDTO(_ attachment: StowAttachment) -> StowAutomationAttachment {
        StowAutomationAttachment(
            id: attachment.id,
            contentType: attachment.contentType,
            fileName: attachment.fileName,
            byteCount: attachment.byteCount,
            pixelWidth: attachment.pixelWidth,
            pixelHeight: attachment.pixelHeight,
            createdAt: attachment.createdAt
        )
    }

    private func snippet(for item: StowItem, query: String?) -> String? {
        let candidates = [item.textContent, item.note, item.urlString, item.linkDescription].compactMap { $0 }
        guard var value = candidates.first(where: { candidate in
            guard let query, !query.isEmpty else { return true }
            return candidate.localizedCaseInsensitiveContains(query)
        }) ?? candidates.first else { return nil }
        value = value.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        guard value.count > 240 else { return value }
        return String(value.prefix(239)) + "…"
    }

    private func failure(
        _ request: StowAutomationRequest,
        code: StowAutomationErrorCode,
        message: String,
        retryable: Bool = false
    ) -> StowAutomationResponse {
        StowAutomationResponse(
            requestID: request.requestID,
            error: StowAutomationError(code: code, message: message, retryable: retryable)
        )
    }
}
