#if DEBUG && targetEnvironment(simulator)
import Foundation
import StowCore

/// Isolated screenshot content. Photographs are supplied by the UI-test bundle, not the app.
enum IOSGalleryTestFixtures {
    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && (
            arguments.contains("--ui-testing-seed-gallery") || arguments.contains("--ui-testing-seed-gallery-pages")
        )
    }

    @MainActor
    static func seed(_ repository: StowRepository) throws {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-gallery-pages") {
            try seedPages(repository)
            return
        }
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

    @MainActor
    static func linkRefreshEnricher() -> LinkMetadataEnricher {
        LinkMetadataEnricher { request, _, _, kind in
            // Keep pull-to-refresh verification offline, with time for the native indicator.
            try await Task.sleep(for: .milliseconds(300))
            guard let url = request.url else { throw URLError(.badURL) }
            let data: Data
            if kind == .html {
                data = Data("""
                <html><head><title>Refreshed link</title>
                <meta name="description" content="Refreshed link description">
                <link rel="icon" href="/icon.jpg">
                <meta property="og:image" content="/preview.jpg">
                </head></html>
                """.utf8)
            } else {
                guard let payload = ProcessInfo.processInfo.environment["STOW_UI_TEST_GALLERY_IMAGES"]?.data(using: .utf8),
                      let encoded = try JSONDecoder().decode([String: String].self, from: payload)["cafe"],
                      let image = Data(base64Encoded: encoded) else { throw CocoaError(.fileReadCorruptFile) }
                data = image
            }
            return BoundedHTTPResponse(data: data, response: URLResponse(
                url: url, mimeType: kind == .html ? "text/html" : "image/jpeg",
                expectedContentLength: data.count, textEncodingName: nil
            ))
        }
    }

    @MainActor
    private static func seedPages(_ repository: StowRepository) throws {
        let now = Date()
        for number in 1...81 {
            _ = try repository.create(from: CaptureDraft(
                type: number.isMultiple(of: 2) ? .text : .code,
                title: String(format: "Gallery item %03d", number),
                textContent: "Saved content \(number).",
                sourceApp: number.isMultiple(of: 2) ? "Notes" : "Safari",
                isPinned: true
            ), at: now.addingTimeInterval(-Double(number) * 60))
        }
    }
}
#endif
