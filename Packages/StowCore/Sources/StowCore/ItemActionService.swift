import Foundation

public enum ItemRetrievalAction: String, CaseIterable, Sendable {
    case copy
    case open
    case share
    case drag
    case preview
}

@MainActor
public final class ItemActionService {
    private let repository: StowRepository

    public init(repository: StowRepository) {
        self.repository = repository
    }

    public func perform(
        itemID: UUID,
        action: ItemRetrievalAction,
        at date: Date = Date(),
        operation: () throws -> Void
    ) throws {
        _ = action
        try operation()
        try repository.recordSuccessfulUse(itemID, at: date)
    }

    public func perform(
        itemID: UUID,
        action: ItemRetrievalAction,
        at date: Date = Date(),
        operation: () async throws -> Void
    ) async throws {
        _ = action
        try await operation()
        try repository.recordSuccessfulUse(itemID, at: date)
    }
}
