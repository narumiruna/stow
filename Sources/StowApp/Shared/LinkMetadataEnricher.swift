import Foundation
import StowCore

enum BoundedHTTPContentKind: Sendable {
    case html
    case image

    func accepts(_ mimeType: String) -> Bool {
        let normalized = mimeType.lowercased()
        switch self {
        case .html:
            return normalized == "text/html" || normalized == "application/xhtml+xml"
        case .image:
            return normalized.hasPrefix("image/")
        }
    }
}

struct BoundedHTTPResponse: Sendable {
    let data: Data
    let response: URLResponse
}

enum BoundedHTTPResponseError: Error, Equatable {
    case unacceptableStatus(Int)
    case responseTooLarge(limit: Int)
    case unsupportedContentType(String)
}

struct BoundedHTTPResponseLoader: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func load(
        _ request: URLRequest,
        byteLimit: Int,
        timeoutInterval: TimeInterval,
        acceptedStatusCodes: Range<Int> = 200..<400,
        contentKind: BoundedHTTPContentKind
    ) async throws -> BoundedHTTPResponse {
        precondition(byteLimit >= 0)
        var request = request
        request.timeoutInterval = timeoutInterval
        let (bytes, response) = try await session.bytes(for: request)
        var completed = false
        defer {
            if !completed { bytes.task.cancel() }
        }

        if let response = response as? HTTPURLResponse,
           !acceptedStatusCodes.contains(response.statusCode) {
            throw BoundedHTTPResponseError.unacceptableStatus(response.statusCode)
        }
        if let mimeType = response.mimeType,
           mimeType.lowercased() != "application/octet-stream",
           !contentKind.accepts(mimeType) {
            throw BoundedHTTPResponseError.unsupportedContentType(mimeType)
        }
        if response.expectedContentLength > Int64(byteLimit) {
            throw BoundedHTTPResponseError.responseTooLarge(limit: byteLimit)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), byteLimit))
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < byteLimit else {
                throw BoundedHTTPResponseError.responseTooLarge(limit: byteLimit)
            }
            data.append(byte)
        }
        completed = true
        return BoundedHTTPResponse(data: data, response: response)
    }
}

@MainActor
struct LinkMetadataEnricher {
    typealias LoadResponse = @Sendable (
        URLRequest,
        Int,
        TimeInterval,
        BoundedHTTPContentKind
    ) async throws -> BoundedHTTPResponse

    private let loadResponse: LoadResponse

    init(loader: BoundedHTTPResponseLoader = BoundedHTTPResponseLoader()) {
        loadResponse = { request, byteLimit, timeoutInterval, contentKind in
            try await loader.load(
                request,
                byteLimit: byteLimit,
                timeoutInterval: timeoutInterval,
                contentKind: contentKind
            )
        }
    }

    init(loadResponse: @escaping LoadResponse) {
        self.loadResponse = loadResponse
    }

    func enrich(item: StowItem, repository: StowRepository) async {
        guard item.type == .link,
              let rawURL = item.urlString,
              let url = URL(string: rawURL),
              item.linkDescription == nil else { return }
        do {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            request.setValue("Stow/0.1", forHTTPHeaderField: "User-Agent")
            let result = try await loadResponse(
                request,
                2 * 1_024 * 1_024,
                12,
                .html
            )
            guard let html = String(data: result.data, encoding: .utf8)
                    ?? String(data: result.data, encoding: .isoLatin1) else { return }
            let parsed = HTMLMetadataParser.parse(html, baseURL: result.response.url ?? url)
            async let favicon = fetchAsset(
                parsed.faviconURL ?? URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL
            )
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
            let result = try await loadResponse(
                URLRequest(url: url),
                5 * 1_024 * 1_024,
                12,
                .image
            )
            return result.data
        } catch {
            return nil
        }
    }
}
