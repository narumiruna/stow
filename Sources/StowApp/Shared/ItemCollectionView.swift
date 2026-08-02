import SwiftData
import SwiftUI
import StowCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ItemCollectionView: View {
    @Environment(AppModel.self) private var appModel
    let items: [StowItem]
    let availableSources: [String]

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 0) {
            filterBar(appModel: appModel)
            if items.isEmpty {
                emptyState
            } else {
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
            }
        }
    }

    @ViewBuilder
    private func filterBar(appModel: AppModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Picker("Type", selection: Binding<ItemType?>(get: { appModel.typeFilter }, set: { appModel.typeFilter = $0 })) {
                Text("All types").tag(ItemType?.none)
                ForEach(ItemType.allCases) { type in Text(type.displayName).tag(Optional(type)) }
            }
            .labelsHidden()
            Picker("Source", selection: Binding<String?>(get: { appModel.sourceFilter }, set: { appModel.sourceFilter = $0 })) {
                Text("All sources").tag(String?.none)
                ForEach(availableSources, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .labelsHidden()
            Picker("Date added", selection: Binding(get: { appModel.dateFilter }, set: { appModel.dateFilter = $0 })) {
                ForEach(DateAddedFilter.allCases) { Text($0.rawValue).tag($0) }
            }
                .labelsHidden()
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
        }
        .accessibilityLabel("Filters")
        .padding(.vertical, 8)
        .background(.bar)
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
                if appModel.selection == .inbox && appModel.searchText.isEmpty {
                    Button("Add Item") { appModel.isAdding = true }
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

    private var emptyTitle: String { appModel.searchText.isEmpty ? "No \(appModel.selection.rawValue) Items" : "No Results" }
    private var emptyIcon: String { appModel.searchText.isEmpty ? appModel.selection.icon : "magnifyingglass" }
    private var emptyDescription: String {
        if !appModel.searchText.isEmpty { return "Try another search or remove a filter." }
        return appModel.selection == .inbox ? "Items you save appear here until you process them." : "Nothing is here yet."
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
                    Text(item.title).font(.headline).lineLimit(1)
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
        #if os(iOS)
        return UIImage(data: data).map(Image.init(uiImage:))
        #elseif os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

private struct ItemContextMenu: View {
    @Environment(AppModel.self) private var appModel
    @Query private var allAttachments: [StowAttachment]
    let item: StowItem

    var body: some View {
        Button { appModel.performUse(item, action: .copy, metric: .itemCopied) { try PlatformActions.copy(item, attachmentData: attachment?.data) } } label: { Label("Copy", systemImage: "doc.on.doc") }
        if item.type == .link || item.type == .file { Button { appModel.performUse(item, action: .open, metric: .itemOpened) { try PlatformActions.open(item, attachment: attachment) } } label: { Label("Open", systemImage: "arrow.up.forward.app") } }
        Button { appModel.togglePin(item) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") }
        if item.status != .trashed { Button { appModel.archiveOrRestore(item) } label: { Label(item.status == .archived ? "Restore to Inbox" : "Archive", systemImage: "archivebox") } }
        Divider()
        Button(role: item.status == .trashed ? nil : .destructive) { appModel.trashOrRestore(item) } label: { Label(item.status == .trashed ? "Restore" : "Move to Trash", systemImage: item.status == .trashed ? "arrow.uturn.backward" : "trash") }
    }

    private var attachment: StowAttachment? { allAttachments.first { $0.itemID == item.id } }
}

extension ItemType {
    var displayName: String {
        switch self { case .link: "Links"; case .text: "Text"; case .code: "Code"; case .image: "Images"; case .file: "Files" }
    }
    var icon: String {
        switch self { case .link: "link"; case .text: "text.alignleft"; case .code: "chevron.left.forwardslash.chevron.right"; case .image: "photo"; case .file: "doc" }
    }
    var tint: Color {
        switch self { case .link: .blue; case .text: .teal; case .code: .purple; case .image: .pink; case .file: .orange }
    }
}

extension StowItem {
    var previewText: String {
        switch type {
        case .link: sourceDomain ?? urlString ?? "Link"
        case .text, .code: textContent ?? ""
        case .image: fileName ?? "Image"
        case .file: fileName ?? "File"
        }
    }
}
