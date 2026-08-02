import Foundation
import StowCore

@MainActor
struct LinkMetadataEnricher {
    func enrich(item: StowItem, repository: StowRepository) async {
        guard item.type == .link, let rawURL = item.urlString, let url = URL(string: rawURL), item.linkDescription == nil else { return }
        do {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
            request.setValue("Stow/0.1", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 2 * 1_024 * 1_024,
                  (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) != false,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            let parsed = HTMLMetadataParser.parse(html, baseURL: response.url ?? url)
            async let favicon = fetchAsset(parsed.faviconURL ?? URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL)
            async let preview = fetchAsset(parsed.previewImageURL)
            let metadata = await LinkMetadata(
                title: parsed.title,
                description: parsed.description,
                domain: url.host?.lowercased(),
                faviconData: favicon,
                previewImageData: preview
            )
            try repository.updateLinkMetadata(item.id, metadata: metadata)
        } catch {
            // Metadata is best effort; the URL remains saved and usable offline.
        }
    }

    private func fetchAsset(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard data.count <= 5 * 1_024 * 1_024,
                  (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) != false else { return nil }
            return data
        } catch { return nil }
    }
}
