#if DEBUG && targetEnvironment(simulator)
import Foundation
import StowCore

/// Isolated screenshot content. Photographs are supplied by the UI-test bundle, not the app.
enum IOSGalleryTestFixtures {
    @MainActor
    static func seed(_ repository: StowRepository) throws {
        guard let payload = ProcessInfo.processInfo.environment["STOW_UI_TEST_GALLERY_IMAGES"]?.data(using: .utf8) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let encodedImages = try JSONDecoder().decode([String: String].self, from: payload)
        var images: [String: Data] = [:]
        for name in ["cafe", "workspace", "mountains"] {
            guard let encoded = encodedImages[name], let data = Data(base64Encoded: encoded) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            images[name] = data
        }
        let now = Date()
        func addLink(_ title: String, domain: String, description: String?, image: String?, age: TimeInterval) throws {
            let item = try repository.create(from: CaptureDraft(
                type: .link,
                title: title,
                urlString: "https://\(domain)/stow-gallery-fixture",
                sourceDomain: domain
            ), at: now.addingTimeInterval(-age))
            try repository.updateLinkMetadata(item.id, metadata: LinkMetadata(
                description: description,
                domain: domain,
                previewImageData: image.flatMap { images[$0] }
            ), at: item.createdAt)
        }
        try addLink(
            "A quiet morning in Kyoto", domain: "instagram.com",
            description: "Small cafés, slow walks, and places worth saving.", image: "cafe", age: 7_200
        )
        try addLink(
            "A simpler way to organize ideas", domain: "threads.com",
            description: "Save first. Sort later. Keep only what matters.", image: nil, age: 86_400
        )
        try addLink(
            "Designing for a calmer digital life", domain: "read.cv",
            description: "Small changes for calmer everyday tools.", image: "workspace", age: 86_460
        )
        try addLink(
            "A weekend in the mountains", domain: "youtube.com",
            description: nil, image: "mountains", age: 172_800
        )
        _ = try repository.create(from: CaptureDraft(
            type: .text, title: "Places to revisit",
            textContent: "A short list of spots I’d like to go back to — while they’re still fresh in my mind."
        ), at: now.addingTimeInterval(-172_860))
        _ = try repository.create(from: CaptureDraft(
            type: .text, title: "Three ideas for a slower week",
            textContent: "More reading, a longer walk, and one screen-free evening."
        ), at: now.addingTimeInterval(-172_920))
        try addLink("instagram.com", domain: "instagram.com", description: nil, image: nil, age: 172_980)
    }
}
#endif
