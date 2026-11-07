import SwiftData
import SwiftUI
import StowCore
import UIKit

enum ItemCollectionLayout: String, CaseIterable, Identifiable {
    case gallery = "Gallery"
    case list = "List"

    var id: String { rawValue }
    var icon: String { self == .gallery ? "square.grid.2x2" : "list.bullet" }
}

struct ItemCollectionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let items: [StowItem]
    let layout: ItemCollectionLayout

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else if layout == .gallery {
                gallery
            } else {
                itemList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var gallery: some View {
        GeometryReader { geometry in
            let viewport = CGRect(
                origin: geometry.frame(in: .global).origin,
                size: CGSize(width: geometry.size.width, height: max(0, geometry.size.height - searchClearance))
            )
            ScrollView {
                MasonryLayout(
                    columnCount: dynamicTypeSize.isAccessibilitySize || geometry.size.width < 340 ? 1 : 2,
                    spacing: 8,
                    layoutDirection: layoutDirection
                ) {
                    ForEach(items) { item in
                        NavigationLink {
                            StowItemDetailView(item: item)
                        } label: {
                            StowItemCard(item: item, viewport: viewport)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("item-\(item.id.uuidString)")
                        .contextMenu { ItemContextMenu(item: item) }
                        .accessibilityActions {
                            Button(item.isPinned ? "Unpin" : "Pin") { appModel.togglePin(item) }
                            if item.status != .trashed {
                                Button(item.status == .archived ? "Restore to Inbox" : "Archive") { appModel.archiveOrRestore(item) }
                            }
                            Button(item.status == .trashed ? "Restore" : "Move to Trash") { appModel.trashOrRestore(item) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .galleryScrollEdges()
            .padding(.bottom, searchClearance)
        }
        .accessibilityIdentifier("item-gallery")
    }

    private var searchClearance: CGFloat {
        if #available(iOS 26.0, *), horizontalSizeClass == .compact, dynamicTypeSize.isAccessibilitySize {
            return 24
        }
        return 0
    }

    private var itemList: some View {
        List(items) { item in
            NavigationLink {
                StowItemDetailView(item: item)
            } label: {
                StowItemRow(item: item)
            }
            .accessibilityIdentifier("item-\(item.id.uuidString)")
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { appModel.togglePin(item) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") }
                    .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if item.status != .trashed {
                    Button { appModel.archiveOrRestore(item) } label: { Label(item.status == .archived ? "Restore" : "Archive", systemImage: "archivebox") }
                        .tint(.blue)
                }
            }
            .contextMenu { ItemContextMenu(item: item) }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("item-list")
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: emptyIcon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(emptyTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(emptyDescription)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if appModel.selection == .inbox && !hasSearchOrFilters {
                    Button("Add Item") { showQuickAdd() }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .controlSize(.large)
                        .frame(minWidth: 96, minHeight: 44)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func showQuickAdd() {
        appModel.isAdding = true
    }

    private var hasSearchOrFilters: Bool {
        !appModel.searchText.isEmpty || appModel.typeFilter != nil || appModel.sourceFilter != nil || appModel.dateFilter != .anytime
    }
    private var emptyTitle: String { hasSearchOrFilters ? "No Results" : "No \(appModel.selection.rawValue) Items" }
    private var emptyIcon: String { hasSearchOrFilters ? "magnifyingglass" : appModel.selection.icon }
    private var emptyDescription: String {
        if hasSearchOrFilters { return "Try another search or remove a filter." }
        return appModel.selection == .inbox ? "Items you save appear here until you process them." : "Nothing is here yet."
    }
}

private extension View {
    @ViewBuilder
    func galleryScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(for: .bottom)
        } else {
            self
        }
    }
}

private struct StowItemRow: View {
    @Query private var allAttachments: [StowAttachment]
    let item: StowItem

    var body: some View {
        HStack(spacing: 12) {
            if item.type == .image, let image = thumbnail {
                image.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: item.type.icon)
                    .font(.title2)
                    .foregroundStyle(item.type.tint)
                    .frame(width: 34, height: 34)
                    .background(item.type.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.displayTitle).font(.headline).lineLimit(1)
                    if item.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange).accessibilityLabel("Pinned") }
                }
                Text(item.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    if let source = item.sourceApp { Text(source) }
                    Text(item.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: Image? {
        guard let attachment = allAttachments.first(where: { $0.itemID == item.id }),
              let data = attachment.thumbnailData ?? Optional(attachment.data) else { return nil }
        return UIImage(data: data).map(Image.init(uiImage:))
    }
}

private struct ItemContextMenu: View {
    @Environment(AppModel.self) private var appModel
    @Query private var allAttachments: [StowAttachment]
    let item: StowItem

    init(item: StowItem) {
        self.item = item
        let itemID = item.id
        _allAttachments = Query(filter: #Predicate<StowAttachment> { $0.itemID == itemID })
    }

    var body: some View {
        Button {
            let representations = appModel.representations(for: item)
            appModel.performUse(item, action: .copy, metric: .itemCopied) {
                try PlatformActions.copy(item, attachmentData: attachment?.data, representations: representations)
            }
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        if item.type == .link || item.type == .file { Button { appModel.performUse(item, action: .open, metric: .itemOpened) { try PlatformActions.open(item, attachment: attachment) } } label: { Label("Open", systemImage: "arrow.up.forward.app") } }
        Button { appModel.togglePin(item) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") }
        if item.status != .trashed { Button { appModel.archiveOrRestore(item) } label: { Label(item.status == .archived ? "Restore to Inbox" : "Archive", systemImage: "archivebox") } }
        Divider()
        Button(role: item.status == .trashed ? nil : .destructive) { appModel.trashOrRestore(item) } label: { Label(item.status == .trashed ? "Restore" : "Move to Trash", systemImage: item.status == .trashed ? "arrow.uturn.backward" : "trash") }
    }

    private var attachment: StowAttachment? { allAttachments.first { $0.itemID == item.id } }
}
