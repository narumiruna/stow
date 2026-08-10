import AppKit
import QuickLook
import SwiftData
import SwiftUI
import StowCore

struct MacLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @Query(sort: \StowItem.createdAt, order: .reverse) private var allItems: [StowItem]
    @Query private var allAttachments: [StowAttachment]

    @State private var selectedIDs: Set<UUID> = []
    @State private var feedback: MacLibraryFeedback?

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 230)
        } content: {
            collection
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 480)
        } detail: {
            detail
                .frame(minWidth: 340)
        }
        .frame(minWidth: 840, minHeight: 560)
        .searchable(text: $appModel.searchText, placement: .toolbar, prompt: "Search saved content")
        .overlay(alignment: .bottom) {
            if let feedback {
                MacLibraryFeedbackView(feedback: feedback, onDismiss: { self.feedback = nil })
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Stow couldn't complete that action", isPresented: Binding(
            get: { appModel.presentedError != nil },
            set: { if !$0 { appModel.presentedError = nil } }
        )) {
            Button("Dismiss", role: .cancel) { appModel.presentedError = nil }
        } message: {
            Text(appModel.presentedError ?? "Unknown error")
        }
        .task { appModel.connect(modelContext) }
        .task(id: searchToken) { await appModel.updateSearch(items: allItems) }
        .onChange(of: appModel.selection) { _, _ in selectedIDs.removeAll() }
        .onChange(of: visibleItems.map(\.id)) { _, validIDs in
            selectedIDs.formIntersection(Set(validIDs))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appModel.runMaintenance() }
        }
        .privacySensitive()
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-drop-target") {
                PanelDropTestTarget()
                    .padding(24)
            }
        }
        .background(MacLibraryWindowConfigurator())
        #endif
    }

    private var sidebar: some View {
        List(selection: Binding<StowSection?>(
            get: { appModel.selection },
            set: { if let section = $0 { appModel.selection = section } }
        )) {
            ForEach(MacLibraryPolicy.sections) { section in
                Label(MacLibraryPolicy.title(for: section), systemImage: section.icon)
                    .tag(section)
                    .accessibilityIdentifier("library-section-\(section.rawValue.lowercased())")
            }
        }
        .navigationTitle("Stow")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    NotificationCenter.default.post(name: .stowShowQuickAdd, object: nil)
                } label: {
                    Label("Quick Add", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("library-quick-add")

                Label {
                    Text(appModel.privacyStorageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: appModel.privacyStorageText.contains("iCloud") ? "lock.icloud" : "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(appModel.privacyStorageText)
                .accessibilityIdentifier("library-storage-status")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var collection: some View {
        VStack(spacing: 0) {
            MacLibraryFilterBar(
                summary: filterSummary,
                type: Binding(get: { appModel.typeFilter }, set: { appModel.typeFilter = $0 }),
                source: Binding(get: { appModel.sourceFilter }, set: { appModel.sourceFilter = $0 }),
                date: Binding(get: { appModel.dateFilter }, set: { appModel.dateFilter = $0 }),
                availableSources: availableSources,
                isSearching: appModel.isSearching,
                onClear: clearFilters
            )
            Divider()
            if visibleItems.isEmpty {
                emptyState
            } else {
                List(selection: $selectedIDs) {
                    ForEach(visibleItems) { item in
                        MacLibraryRow(item: item, attachment: attachmentMap[item.id])
                            .tag(item.id)
                            .contextMenu { contextMenu(for: item) }
                            .accessibilityIdentifier("library-item-\(item.id.uuidString)")
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("library-item-list")
            }
        }
        .navigationTitle(MacLibraryPolicy.title(for: appModel.selection))
    }

    @ViewBuilder
    private var detail: some View {
        let selected = selectedItems
        if selected.count > 1 {
            MacLibraryBatchDetail(
                items: selected,
                onSetPinned: setPinned,
                onLifecycle: performLifecycle,
                onTrash: moveToTrash,
                onRestore: restoreFromTrash
            )
        } else if let item = selected.first {
            MacLibraryDetailView(
                item: item,
                attachments: allAttachments.filter { $0.itemID == item.id },
                onSetPinned: { setPinned([$0], pinned: $1) },
                onArchiveOrRestore: { performLifecycle([$0]) },
                onTrash: { moveToTrash([$0]) },
                onRestore: { restoreFromTrash([$0.id]) }
            )
            .id(item.id)
        } else {
            ContentUnavailableView(
                "Choose an item",
                systemImage: "shippingbox",
                description: Text("Preview its contents, edit details, or manage its Library status.")
            )
            .accessibilityIdentifier("library-empty-detail")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let state = MacLibraryPolicy.emptyState(
            section: appModel.selection,
            hasSearchText: !appModel.searchText.isEmpty,
            hasFilters: filterSummary.count > 0
        )
        ContentUnavailableView {
            Label(emptyTitle(for: state), systemImage: emptyIcon(for: state))
        } description: {
            Text(emptyDescription(for: state))
        } actions: {
            if state == .noResults {
                Button("Clear Search and Filters") {
                    appModel.searchText = ""
                    clearFilters()
                }
                .accessibilityIdentifier("library-clear-search-filters")
            } else if state == .emptyInbox {
                Button("Quick Add") {
                    NotificationCenter.default.post(name: .stowShowQuickAdd, object: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityIdentifier("library-empty-state")
    }

    @ViewBuilder
    private func contextMenu(for item: StowItem) -> some View {
        Button {
            appModel.performUse(item, action: .copy, metric: .itemCopied) {
                try PlatformActions.copy(item, attachmentData: attachmentMap[item.id]?.data, attachment: attachmentMap[item.id])
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if item.type == .link || item.type == .file {
            Button {
                appModel.performUse(item, action: .open, metric: .itemOpened) {
                    try PlatformActions.open(item, attachment: attachmentMap[item.id])
                }
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
        }
        Divider()
        if item.status != .trashed {
            Button { setPinned([item], pinned: !item.isPinned) } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Button { performLifecycle([item]) } label: {
                Label(item.status == .archived ? "Restore to Inbox" : "Archive", systemImage: "archivebox")
            }
            Button(role: .destructive) { moveToTrash([item]) } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        } else {
            Button { restoreFromTrash([item.id]) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var visibleItems: [StowItem] {
        allItems.filter { item in
            sectionIncludes(item) && filtersInclude(item) && searchIncludes(item)
        }
        .sorted(by: sectionSort)
    }

    private var selectedItems: [StowItem] {
        visibleItems.filter { selectedIDs.contains($0.id) }
    }

    private var attachmentMap: [UUID: StowAttachment] {
        Dictionary(allAttachments.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var availableSources: [String] {
        Array(Set(allItems.compactMap(\.sourceApp))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var filterSummary: MacLibraryFilterSummary {
        MacLibraryFilterSummary(type: appModel.typeFilter, source: appModel.sourceFilter, date: appModel.dateFilter)
    }

    private func clearFilters() {
        appModel.typeFilter = nil
        appModel.sourceFilter = nil
        appModel.dateFilter = .anytime
    }

    private func sectionIncludes(_ item: StowItem) -> Bool {
        switch appModel.selection {
        case .inbox: item.status == .inbox
        case .recent: item.status != .trashed && item.lastUsedAt != nil
        case .pinned: item.status != .trashed && item.isPinned
        case .archive: item.status == .archived
        case .trash: item.status == .trashed
        case .settings: false
        }
    }

    private func filtersInclude(_ item: StowItem) -> Bool {
        (appModel.typeFilter == nil || item.type == appModel.typeFilter) &&
            (appModel.sourceFilter == nil || item.sourceApp == appModel.sourceFilter) &&
            appModel.dateFilter.includes(item.createdAt)
    }

    private func searchIncludes(_ item: StowItem) -> Bool {
        guard !appModel.searchText.isEmpty else { return true }
        if let resultIDs = appModel.searchResultIDs { return resultIDs.contains(item.id) }
        let query = appModel.searchText.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? appModel.searchText
        return [item.title, item.textContent, item.urlString, item.sourceDomain, item.note, item.fileName]
            .compactMap { $0 }
            .contains {
                let value = $0.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? $0
                return value.localizedCaseInsensitiveContains(query)
            }
    }

    private func sectionSort(_ lhs: StowItem, _ rhs: StowItem) -> Bool {
        if appModel.selection == .recent {
            return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
        }
        return lhs.createdAt > rhs.createdAt
    }

    private func setPinned(_ items: [StowItem], pinned: Bool) {
        guard appModel.setPinned(items, pinned: pinned) else { return }
        showFeedback(pinned ? "Pinned" : "Unpinned")
    }

    private func performLifecycle(_ items: [StowItem]) {
        guard let action = MacLibraryPolicy.lifecycleAction(for: items), appModel.archiveOrRestore(items) else { return }
        switch action {
        case .archive: showFeedback(items.count == 1 ? "Archived" : "Archived \(items.count) items")
        case .restoreToInbox: showFeedback(items.count == 1 ? "Restored to Inbox" : "Restored \(items.count) items to Inbox")
        }
    }

    private func moveToTrash(_ items: [StowItem]) {
        let ids = items.map(\.id)
        guard !ids.isEmpty, appModel.moveToTrash(items) else { return }
        selectedIDs.subtract(ids)
        feedback = MacLibraryFeedback(
            message: ids.count == 1 ? "Moved to Trash" : "Moved \(ids.count) items to Trash",
            actionTitle: "Undo",
            action: { restoreFromTrash(ids) }
        )
    }

    private func restoreFromTrash(_ ids: [UUID]) {
        guard appModel.restoreFromTrash(ids: ids) else { return }
        showFeedback(ids.count == 1 ? "Restored from Trash" : "Restored \(ids.count) items from Trash")
    }

    private func showFeedback(_ message: String) {
        feedback = MacLibraryFeedback(message: message)
    }

    private func emptyTitle(for state: MacLibraryEmptyState) -> String {
        switch state {
        case .noResults: "No Results"
        case .emptyInbox: "Inbox is Empty"
        case .emptySection(let section): "Nothing in \(MacLibraryPolicy.title(for: section))"
        }
    }

    private func emptyIcon(for state: MacLibraryEmptyState) -> String {
        switch state {
        case .noResults: "magnifyingglass"
        case .emptyInbox: StowSection.inbox.icon
        case .emptySection(let section): section.icon
        }
    }

    private func emptyDescription(for state: MacLibraryEmptyState) -> String {
        switch state {
        case .noResults: "Try another search or remove one or more filters."
        case .emptyInbox: "New captures that need attention will appear here."
        case .emptySection(.recent): "Items appear here after you explicitly copy, open, preview, share, or drag them."
        case .emptySection(.pinned): "Pin an item to keep it easy to find."
        case .emptySection(.archive): "Items you finish processing remain available here."
        case .emptySection(.trash): "Items moved to Trash remain recoverable for 30 days."
        case .emptySection: "Nothing is here yet."
        }
    }

    private var searchToken: String {
        var versionHasher = Hasher()
        for item in allItems {
            versionHasher.combine(item.id)
            versionHasher.combine(item.updatedAt)
        }
        return [
            appModel.selection.rawValue,
            appModel.searchText,
            appModel.typeFilter?.rawValue ?? "",
            appModel.sourceFilter ?? "",
            appModel.dateFilter.rawValue,
            "\(allItems.count):\(versionHasher.finalize())"
        ].joined(separator: "¦")
    }
}

private struct MacLibraryFilterBar: View {
    let summary: MacLibraryFilterSummary
    @Binding var type: ItemType?
    @Binding var source: String?
    @Binding var date: DateAddedFilter
    let availableSources: [String]
    let isSearching: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            filterMenu
            if summary.count > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        ForEach(summary.tokens) { token in tokenButton(token) }
                    }
                    Text(summary.compactLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(summary.count) Library filters applied")
                }
                .layoutPriority(1)
                Button("Clear") { onClear() }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear Library filters")
            }
            Spacer(minLength: 0)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching Library")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-filter-bar")
    }

    private var filterMenu: some View {
        Menu {
            Menu("Content Type") {
                filterButton("Any Type", selected: type == nil) { type = nil }
                ForEach(ItemType.allCases) { itemType in
                    filterButton(itemType.displayName, selected: type == itemType) { type = itemType }
                }
            }
            Menu("Source App") {
                filterButton("Any App", selected: source == nil) { source = nil }
                ForEach(availableSources, id: \.self) { app in
                    filterButton(app, selected: source == app) { source = app }
                }
            }
            Menu("Date Added") {
                ForEach(DateAddedFilter.allCases) { filter in
                    filterButton(filter.rawValue, selected: date == filter) { date = filter }
                }
            }
            if summary.count > 0 {
                Divider()
                Button("Clear Filters", action: onClear)
            }
        } label: {
            Label(summary.count == 0 ? "Filter" : "Filter (\(summary.count))", systemImage: "line.3.horizontal.decrease.circle")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("library-filter-menu")
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private func tokenButton(_ token: MacLibraryFilterToken) -> some View {
        Button {
            switch token.kind {
            case .type: type = nil
            case .source: source = nil
            case .date: date = .anytime
            }
        } label: {
            HStack(spacing: 4) {
                Text(token.title)
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Remove \(token.title) filter")
        .accessibilityLabel("Remove \(token.title) filter")
    }
}

private struct MacLibraryRow: View {
    let item: StowItem
    let attachment: StowAttachment?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(item.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        if let source = item.sourceApp { Text(source) }
                        Text(item.createdAt, style: .relative)
                    }
                    Text(item.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(item.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.type == .image,
           let data = attachment?.thumbnailData ?? attachment?.data,
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: item.type.icon)
                .font(.title3)
                .foregroundStyle(item.type.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(item.type.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var accessibilityValue: String {
        [item.previewText, item.sourceApp, item.createdAt.formatted(date: .abbreviated, time: .shortened)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct MacLibraryBatchDetail: View {
    let items: [StowItem]
    let onSetPinned: ([StowItem], Bool) -> Void
    let onLifecycle: ([StowItem]) -> Void
    let onTrash: ([StowItem]) -> Void
    let onRestore: ([UUID]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("\(items.count) Items Selected", systemImage: "checkmark.circle")
                .font(.title2.bold())
            Text("Apply one Library action to the complete selection.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if items.allSatisfy({ $0.status == .trashed }) {
                    Button { onRestore(items.map(\.id)) } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if let pinAction = MacLibraryPolicy.pinAction(for: items) {
                        Button { onSetPinned(items, pinAction == .pinAll) } label: {
                            Label(pinAction.title, systemImage: pinAction.systemImage)
                        }
                    }
                    if let lifecycle = MacLibraryPolicy.lifecycleAction(for: items) {
                        Button { onLifecycle(items) } label: {
                            Label(lifecycle.title, systemImage: "archivebox")
                        }
                    }
                    Button(role: .destructive) { onTrash(items) } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
            }
            .controlSize(.large)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("library-batch-detail")
    }
}

private struct MacLibraryFeedback {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
}

private struct MacLibraryFeedbackView: View {
    let feedback: MacLibraryFeedback
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(feedback.message)
            if let title = feedback.actionTitle, let action = feedback.action {
                Button(title) {
                    action()
                    onDismiss()
                }
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.28)))
        .shadow(radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-feedback")
    }
}

private struct MacLibraryDetailView: View {
    @Environment(AppModel.self) private var appModel
    let item: StowItem
    let attachments: [StowAttachment]
    let onSetPinned: (StowItem, Bool) -> Void
    let onArchiveOrRestore: (StowItem) -> Void
    let onTrash: (StowItem) -> Void
    let onRestore: (StowItem) -> Void

    @State private var editing = false
    @State private var previewURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                contentPreview
                Divider()
                metadata
                actionBar
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                managementMenu
                Button("Edit") { editing = true }
                    .accessibilityIdentifier("library-edit-item")
            }
        }
        .sheet(isPresented: $editing) {
            MacLibraryEditSheet(item: item) { draft in
                appModel.saveForPanel(
                    item,
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    note: draft.note.trimmedOrNil,
                    text: item.type == .text || item.type == .code ? draft.text : item.textContent,
                    language: draft.language.trimmedOrNil
                )
            }
        }
        .quickLookPreview($previewURL)
        .accessibilityIdentifier("library-item-detail")
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .link:
            VStack(alignment: .leading, spacing: 12) {
                if let data = item.linkPreviewImageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(item.title).font(.title2.bold())
                Text(item.sourceDomain ?? item.urlString ?? "")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let description = item.linkDescription { Text(description) }
            }
            .onDrag { dragProvider() }
        case .text:
            Text(item.textContent ?? "")
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onDrag { dragProvider() }
        case .code:
            ScrollView(.horizontal) {
                Text(SimpleSyntaxHighlighter.highlight(item.textContent ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .onDrag { dragProvider() }
        case .image:
            if let data = attachments.first?.data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onDrag { dragProvider(attachments.first) }
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
            }
        case .file:
            VStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                Text(item.fileName ?? item.title)
                    .font(.title3)
                    .textSelection(.enabled)
                if let attachment = attachments.first {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .onDrag { dragProvider(attachments.first) }
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            metadataRow("Title", item.title)
            if let note = item.note, !note.isEmpty { metadataRow("Note", note) }
            metadataRow("Added", item.createdAt.formatted(date: .abbreviated, time: .shortened))
            metadataRow("Last used", item.lastUsedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            metadataRow("Source", item.sourceApp ?? "Unknown")
            if let url = item.urlString { metadataRow("Original URL", url) }
            if item.type == .code { metadataRow("Language", item.language ?? "Plain text") }
        }
        .textSelection(.enabled)
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { primaryActions }
            VStack(alignment: .leading, spacing: 10) { primaryActions }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryActions: some View {
        Button {
            appModel.performUse(item, action: .copy, metric: .itemCopied) {
                try PlatformActions.copy(item, attachmentData: attachments.first?.data, attachment: attachments.first)
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)

        if item.type == .link || item.type == .file {
            Button {
                appModel.performUse(item, action: .open, metric: .itemOpened) {
                    try PlatformActions.open(item, attachment: attachments.first)
                }
            } label: {
                Label(item.type == .link ? "Open Link" : "Open", systemImage: "arrow.up.forward.app")
            }
        }
        if item.type == .file, let attachment = attachments.first {
            Button {
                appModel.performUse(item, action: .preview, metric: .itemOpened) {
                    previewURL = try PlatformActions.materialize(attachment)
                }
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
        }
        StowShareButton(item: item, attachment: attachments.first)
    }

    private var managementMenu: some View {
        Menu("Manage") {
            if item.status == .trashed {
                Button { onRestore(item) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button { onSetPinned(item, !item.isPinned) } label: {
                    Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                Button { onArchiveOrRestore(item) } label: {
                    Label(item.status == .archived ? "Restore to Inbox" : "Archive", systemImage: "archivebox")
                }
                Divider()
                Button(role: .destructive) { onTrash(item) } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("library-manage-item")
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dragProvider(_ attachment: StowAttachment? = nil) -> NSItemProvider {
        let success = MacLibraryDragSuccessToken { appModel.markUsed(item, metric: .itemDragged) }
        let provider = NSItemProvider()
        let payload = DragPayload(item: item, attachment: attachment)
        provider.suggestedName = payload.suggestedName
        provider.registerDataRepresentation(forTypeIdentifier: payload.typeIdentifier, visibility: .all) { completion in
            completion(payload.data, nil)
            success.record()
            return nil
        }
        return provider
    }
}

private struct MacLibraryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: StowItem
    let save: (MacLibraryEditDraft) -> String?

    @State private var draft: MacLibraryEditDraft
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false
    @FocusState private var titleFocused: Bool

    init(item: StowItem, save: @escaping (MacLibraryEditDraft) -> String?) {
        self.item = item
        self.save = save
        _draft = State(initialValue: MacLibraryEditDraft(item: item))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Edit Item").font(.headline)
                Spacer()
                Button("Save Changes", action: saveChanges)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("library-save-changes")
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Dismiss") { self.errorMessage = nil }
                                .buttonStyle(.borderless)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("library-edit-error")
                    }
                    TextField("Title", text: $draft.title)
                        .focused($titleFocused)
                        .accessibilityIdentifier("library-edit-title")
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                    if item.type == .text || item.type == .code {
                        TextEditor(text: $draft.text)
                            .font(item.type == .code ? .system(.body, design: .monospaced) : .body)
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        if item.type == .code {
                            TextField("Language", text: $draft.language)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 380, idealHeight: 520)
        .interactiveDismissDisabled(draft.isDirty(comparedWith: item))
        .alert("Discard unsaved changes?", isPresented: $confirmingDiscard) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Your saved item will remain unchanged.")
        }
        .onAppear { titleFocused = true }
    }

    private func cancel() {
        if draft.isDirty(comparedWith: item) { confirmingDiscard = true }
        else { dismiss() }
    }

    private func saveChanges() {
        if let message = save(draft) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

@MainActor
private final class MacLibraryDragSuccessToken: @unchecked Sendable {
    private let success: @MainActor () -> Void

    init(success: @escaping @MainActor () -> Void) { self.success = success }

    nonisolated func record() {
        Task { @MainActor in success() }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#if DEBUG
private struct MacLibraryWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window,
              ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        window.identifier = NSUserInterfaceItemIdentifier("stow-library-window")
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-testing-library-size=") }) else { return }
        let rawSize = argument.replacingOccurrences(of: "--ui-testing-library-size=", with: "")
        let components = rawSize.split(separator: "x").compactMap { Double($0) }
        guard components.count == 2 else { return }
        let size = NSSize(width: max(840, components[0]), height: max(560, components[1]))
        guard window.contentLayoutRect.size != size else { return }
        window.setContentSize(size)
        window.center()
    }
}
#endif
