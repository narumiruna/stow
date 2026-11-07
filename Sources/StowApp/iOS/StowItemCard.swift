import ImageIO
import SwiftData
import SwiftUI
import StowCore
import UIKit

struct StowItemCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var attachments: [StowAttachment]
    @State private var previewImage: UIImage?
    @State private var mediaAspectRatio: CGFloat?
    @State private var isVisible = false
    let item: StowItem
    let viewport: CGRect

    init(item: StowItem, viewport: CGRect) {
        self.item = item
        self.viewport = viewport
        let itemID = item.id
        _attachments = Query(filter: #Predicate<StowAttachment> { $0.itemID == itemID })
    }

    var body: some View {
        let presentation = ItemCardPresentation(item: item)
        VStack(alignment: .leading, spacing: 0) {
            if let mediaAspectRatio {
                Color(uiColor: .secondarySystemBackground)
                    .aspectRatio(dynamicTypeSize.isAccessibilitySize ? max(1.6, mediaAspectRatio) : mediaAspectRatio, contentMode: .fit)
                    .overlay {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview for \(presentation.title)")
                    .accessibilityIdentifier(previewImage == nil ? "item-preview-loading-\(item.id.uuidString)" : "item-preview-\(item.id.uuidString)")
            }
            VStack(alignment: .leading, spacing: 6) {
                if mediaAspectRatio == nil {
                    HStack {
                        Image(systemName: item.type == .link && presentation.excerpt != nil ? "quote.opening" : item.type.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        if item.isPinned { pinnedIndicator }
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Text(presentation.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("card-title-\(item.id.uuidString)")
                    if mediaAspectRatio != nil && item.isPinned { pinnedIndicator }
                }
                if let excerpt = presentation.excerpt {
                    Text(excerpt)
                        .font(item.type == .code ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(Color(uiColor: .label).opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(sourceLabel(presentation)) · \(item.createdAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .label).opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(uiColor: .separator).opacity(contrast == .increased ? 1 : 0.4), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { isVisible = geometry.frame(in: .global).intersects(viewport.insetBy(dx: 0, dy: -200)) }
                    .onChange(
                        of: geometry.frame(in: .global).intersects(viewport.insetBy(dx: 0, dy: -200))
                    ) { _, visible in isVisible = visible }
            }
        }
        .task(id: PreviewRequest(isVisible: isVisible, itemRevision: item.updatedAt, attachmentID: attachments.first?.id)) {
            guard isVisible else {
                previewImage = nil
                return
            }
            guard let data = previewData else {
                previewImage = nil
                mediaAspectRatio = nil
                return
            }
            let image = await Task.detached(priority: .utility) { Self.decodePreview(data) }.value
            guard !Task.isCancelled else { return }
            previewImage = image.map { UIImage(cgImage: $0) }
            mediaAspectRatio = previewImage.map(previewAspectRatio)
        }
        .onDisappear {
            isVisible = false
            previewImage = nil
        }
    }

    private struct PreviewRequest: Hashable {
        let isVisible: Bool
        let itemRevision: Date
        let attachmentID: UUID?
    }

    private var pinnedIndicator: some View {
        Image(systemName: "pin.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Pinned")
    }

    private var previewData: Data? {
        if item.type == .link { return item.linkPreviewImageData }
        guard let attachment = attachments.first else { return nil }
        return attachment.thumbnailData ?? (item.type == .image ? attachment.data : nil)
    }

    private func sourceLabel(_ presentation: ItemCardPresentation) -> String {
        presentation.source.localizedCaseInsensitiveCompare(presentation.title) == .orderedSame && item.type == .link
            ? "Link" : presentation.source
    }

    private func previewAspectRatio(_ image: UIImage) -> CGFloat {
        guard image.size.height > 0 else { return 1 }
        return min(1.8, max(0.75, image.size.width / image.size.height))
    }

    nonisolated private static func decodePreview(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 768,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return image
    }
}
