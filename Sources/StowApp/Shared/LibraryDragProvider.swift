import Foundation
import StowCore

@MainActor
enum LibraryDragProvider {
    static func make(
        payload: DragPayload,
        onLoad: @escaping @MainActor @Sendable () -> Void
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = payload.suggestedName
        provider.registerDataRepresentation(forTypeIdentifier: payload.typeIdentifier, visibility: .all) { completion in
            completion(payload.data, nil)
            // Library accounting follows each data request, not destination drag acceptance.
            Task { @MainActor in onLoad() }
            return nil
        }
        return provider
    }
}
