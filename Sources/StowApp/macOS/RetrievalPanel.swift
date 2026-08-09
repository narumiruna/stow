import AppKit
import SwiftData
import SwiftUI
import StowCore
import UniformTypeIdentifiers

enum RetrievalPanelMode: String, CaseIterable, Identifiable {
    case clipboard = "Clipboard"
    case inbox = "Inbox"
    case pinned = "Pinned"
    case archive = "Archive"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .clipboard: "clock.arrow.circlepath"
        case .inbox: "tray"
        case .pinned: "pin.fill"
        case .archive: "archivebox"
        }
    }

    var color: Color {
        switch self {
        case .clipboard: .secondary
        case .inbox: .red
        case .pinned: .green
        case .archive: .orange
        }
    }
}

private enum RetrievalPopoverKind {
    case preview
    case edit
    case rename
}

struct RetrievalPanelView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \StowItem.createdAt, order: .reverse) private var allItems: [StowItem]
    @Query private var allAttachments: [StowAttachment]
    @ObservedObject var session: RetrievalPanelSession

    let onDismiss: (Bool) -> Void
    let onResize: (CGFloat, Bool) -> Void
    let onUse: (StowItem, StowAttachment?, RetrievalUseKind) -> Void
    let onOpenLibrary: () -> Void
    let onQuickAdd: () -> Void

    @State private var mode: RetrievalPanelMode = .clipboard
    @State private var query = ""
    @State private var typeFilter: ItemType?
    @State private var sourceFilter: String?
    @State private var dateFilter: DateAddedFilter = .anytime
    @State private var searchActive = false
    @State private var searchResultIDs: [UUID]?
    @State private var resolvedSearchToken: String?
    @State private var selection: UUID?
    @State private var selectedIDs: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var popoverItemID: UUID?
    @State private var popoverKind: RetrievalPopoverKind?
    @State private var monitoringEnabled = UserDefaults.standard.object(forKey: "clipboardMonitoringEnabled") == nil || UserDefaults.standard.bool(forKey: "clipboardMonitoringEnabled")
    @State private var attachmentLookup: [UUID: StowAttachment] = [:]
    @FocusState private var searchFocused: Bool
    @FocusState private var timelineFocused: Bool

    private var isCompact: Bool { session.panelHeight < 275 }

    private var attachments: [UUID: StowAttachment] { attachmentLookup }

    private var modeItems: [StowItem] {
        allItems.filter { item in
            switch mode {
            case .clipboard: item.status != .trashed
            case .inbox: item.status == .inbox
            case .pinned: item.status != .trashed && item.isPinned
            case .archive: item.status == .archived
            }
        }
    }

    private var items: [StowItem] {
        let base = modeItems
        if let searchResultIDs, resolvedSearchToken == searchToken {
            let byID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return searchResultIDs.compactMap { byID[$0] }
        }
        if !query.isEmpty || hasFilters {
            return base.filter(localSearchIncludes).sorted(by: panelSort)
        }
        return base.sorted(by: panelSort)
    }

    private var availableSources: [String] {
        Array(Set(allItems.compactMap(\.sourceApp))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View { keyboardObservedPanel }

    private var panelSurface: some View {
        GeometryReader { geometry in
            ZStack {
                RetrievalPanelMaterial()
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.accentColor.opacity(0.05), Color.black.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 0) {
                    resizeHandle(currentHeight: geometry.size.height)
                    toolbar
                    timeline
                }
                if let feedback = session.feedback {
                    feedbackPill(feedback)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: searchActive)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isCompact)
        }
        .frame(minWidth: 480, minHeight: RetrievalPanelGeometry.minimumHeight)
        .focusable()
        .focused($timelineFocused)
        .focusEffectDisabled()
    }

    private var observedPanel: some View {
        panelSurface
            .overlay { keyboardCommands }
            .task(id: searchToken) { await updateSearch() }
            .onAppear {
                rebuildAttachmentLookup()
                repairSelection()
                timelineFocused = true
                session.acceptsPreviewShortcut = true
            }
            .onChange(of: items.map(\.id)) { _, _ in repairSelection() }
            .onChange(of: attachmentToken) { _, _ in rebuildAttachmentLookup() }
            .onChange(of: mode) { _, _ in
                selectedIDs.removeAll()
                selection = nil
                repairSelection()
            }
            .onChange(of: session.previewGeneration) { _, _ in previewSelected() }
            .onChange(of: session.escapeGeneration) { _, _ in handleEscape() }
            .onChange(of: searchFocused) { _, focused in session.acceptsPreviewShortcut = !focused }
    }

    private var keyboardObservedPanel: some View {
        observedPanel
            .onKeyPress(.leftArrow) {
                moveSelection(by: -1, extending: NSEvent.modifierFlags.contains(.shift))
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveSelection(by: 1, extending: NSEvent.modifierFlags.contains(.shift))
                return .handled
            }
            .onKeyPress(.downArrow) {
                timelineFocused = true
                return .handled
            }
            .onKeyPress(.upArrow) {
                if searchActive { searchFocused = true }
                return .handled
            }
            .onKeyPress { press in handleTypedKey(press) }
            .alert("Stow couldn't complete that action", isPresented: Binding(
                get: { appModel.presentedError != nil },
                set: { if !$0 { appModel.presentedError = nil } }
            )) {
                Button("OK", role: .cancel) { appModel.presentedError = nil }
            } message: {
                Text(appModel.presentedError ?? "Unknown error")
            }
    }

    private var toolbar: some View {
        HStack(spacing: isCompact ? 8 : 11) {
            if searchActive {
                searchBar
                compactModeDots
            } else {
                Spacer(minLength: 0)
                Button { activateSearch() } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                .accessibilityIdentifier("panel-search")

                ForEach(RetrievalPanelMode.allCases.filter { $0 != .archive }) { toolbarMode in
                    modeChip(toolbarMode)
                }

                Button(action: onQuickAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quick Add")

                panelMenu
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, isCompact ? 14 : 18)
        .frame(height: isCompact ? 48 : 58)
        .background(.ultraThinMaterial.opacity(0.42))
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            if let typeFilter {
                filterToken(typeFilter.singularPanelName, color: typeFilter.panelColor) { self.typeFilter = nil }
            }
            if let sourceFilter {
                filterToken(sourceFilter, color: .blue) { self.sourceFilter = nil }
            }
            if dateFilter != .anytime {
                filterToken(dateFilter.rawValue, color: .orange) { dateFilter = .anytime }
            }
            TextField("Search Stow", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                .focused($searchFocused)
                .onSubmit { performDefault() }
                .onKeyPress(.tab) {
                    searchFocused = false
                    timelineFocused = true
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    searchFocused = false
                    timelineFocused = true
                    return .handled
                }
                .accessibilityIdentifier("Search Stow")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
            }
            filterMenu
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: 760)
        .frame(height: isCompact ? 36 : 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(searchFocused ? 0.9 : 0.35), lineWidth: searchFocused ? 2 : 1))
    }

    private var compactModeDots: some View {
        HStack(spacing: 8) {
            ForEach(RetrievalPanelMode.allCases.filter { $0 != .archive }) { toolbarMode in
                Button { mode = toolbarMode } label: {
                    Circle()
                        .fill(toolbarMode == mode ? Color.accentColor : toolbarMode.color)
                        .frame(width: toolbarMode == mode ? 13 : 10, height: toolbarMode == mode ? 13 : 10)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(toolbarMode.rawValue)
            }
            panelMenu
        }
    }

    private func modeChip(_ toolbarMode: RetrievalPanelMode) -> some View {
        Button { mode = toolbarMode } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(toolbarMode.color)
                    .frame(width: 9, height: 9)
                if !isCompact || toolbarMode == mode {
                    Text(toolbarMode.rawValue)
                        .lineLimit(1)
                }
            }
            .font(.system(size: isCompact ? 13 : 14, weight: toolbarMode == mode ? .semibold : .medium))
            .padding(.horizontal, isCompact ? 9 : 12)
            .frame(height: 34)
            .background(toolbarMode == mode ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(toolbarMode == mode ? Color.primary.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mode-\(toolbarMode.rawValue.lowercased())")
    }

    private var panelMenu: some View {
        Menu {
            Button { mode = .archive } label: { Label("Archive", systemImage: "archivebox") }
            Button(action: onQuickAdd) { Label("Quick Add", systemImage: "plus") }
            Button(action: onOpenLibrary) { Label("Open Library", systemImage: "macwindow") }
            Divider()
            Toggle("Monitor Clipboard", isOn: $monitoringEnabled)
            SettingsLink { Label("Settings", systemImage: "gear") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("More")
        .onChange(of: monitoringEnabled) { _, enabled in
            UserDefaults.standard.set(enabled, forKey: "clipboardMonitoringEnabled")
            NotificationCenter.default.post(name: .stowClipboardMonitoringChanged, object: nil)
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Content Type") {
                Button("Any type") { typeFilter = nil }
                ForEach(ItemType.allCases) { type in
                    Button { typeFilter = type } label: { Label(type.displayName, systemImage: type.icon) }
                }
            }
            Section("Source App") {
                Button("Any app") { sourceFilter = nil }
                ForEach(availableSources, id: \.self) { source in
                    Button(source) { sourceFilter = source }
                }
            }
            Section("Date Added") {
                ForEach(DateAddedFilter.allCases) { filter in
                    Button(filter.rawValue) { dateFilter = filter }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Search Filters")
        .accessibilityIdentifier("panel-filters")
    }

    private func filterToken(_ title: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(title) filter")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .frame(height: 25)
        .background(.quaternary, in: Capsule())
    }

    private var timeline: some View {
        let attachmentMap = attachments
        return GeometryReader { geometry in
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: query.isEmpty ? mode.icon : "magnifyingglass")
                        .font(.system(size: isCompact ? 25 : 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(query.isEmpty ? "Nothing in \(mode.rawValue)" : "No Results")
                        .font(.headline)
                    if !query.isEmpty || hasFilters {
                        Button("Clear Search and Filters") { clearSearch() }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: isCompact ? 11 : 14) {
                            ForEach(items) { item in
                                clipButton(item, attachment: attachmentMap[item.id], availableHeight: geometry.size.height)
                                    .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, isCompact ? 14 : 18)
                        .padding(.top, isCompact ? 9 : 12)
                        .padding(.bottom, isCompact ? 12 : 16)
                    }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .onChange(of: selection) { _, id in
                        if let id {
                            if reduceMotion { proxy.scrollTo(id, anchor: .center) }
                            else { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) } }
                        }
                    }
                }
            }
        }
    }

    private func clipButton(_ item: StowItem, attachment: StowAttachment?, availableHeight: CGFloat) -> some View {
        let selected = selectedIDs.contains(item.id)
        return Button { select(item) } label: {
            StowTimelineCard(
                item: item,
                attachment: attachment,
                isSelected: selected,
                isCompact: isCompact
            )
            .frame(width: isCompact ? 176 : 224, height: max(128, availableHeight - (isCompact ? 21 : 28)))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            select(item, ignoringModifiers: true)
            onUse(item, attachment, .defaultPaste)
        })
        .contextMenu { cardContextMenu(item, attachment: attachment) }
        .onDrag { dragProvider(item, attachment: attachment) }
        .popover(isPresented: popoverBinding(for: item.id), arrowEdge: .top) {
            RetrievalItemPopover(
                item: item,
                attachment: attachment,
                kind: popoverKind ?? .preview,
                onSave: { title, note, text, language in
                    appModel.save(item, title: title, note: note, text: text, language: language)
                    popoverItemID = nil
                    popoverKind = nil
                },
                onCancel: {
                    popoverItemID = nil
                    popoverKind = nil
                },
                onOpen: { onUse(item, attachment, .open) }
            )
        }
        .accessibilityIdentifier("panel-item-\(item.id.uuidString)")
    }

    @ViewBuilder
    private func cardContextMenu(_ item: StowItem, attachment: StowAttachment?) -> some View {
        Button { onUse(item, attachment, .defaultPaste) } label: { Label("Use", systemImage: "return") }
        Button { onUse(item, attachment, .copy) } label: { Label("Copy", systemImage: "doc.on.doc") }
        if item.type == .link || item.type == .file {
            Button { onUse(item, attachment, .open) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
        }
        Button { showPopover(.preview, for: item) } label: { Label("Preview", systemImage: "eye") }
        if item.type == .text || item.type == .code {
            Button { showPopover(.edit, for: item) } label: { Label("Edit", systemImage: "pencil") }
        }
        Button { showPopover(.rename, for: item) } label: { Label("Rename", systemImage: "text.cursor") }
        Divider()
        Button { appModel.togglePin(item) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") }
        Button { appModel.archiveOrRestore(item) } label: { Label(item.status == .archived ? "Restore to Inbox" : "Archive", systemImage: "archivebox") }
        Button(role: .destructive) { appModel.trashOrRestore(item) } label: { Label("Move to Trash", systemImage: "trash") }
    }

    private var keyboardCommands: some View {
        let attachmentMap = attachments
        return ZStack {
            Button("") { handleEscape() }.keyboardShortcut(.cancelAction).hidden()
            Button("") { performDefault() }.keyboardShortcut(.return, modifiers: []).hidden()
            Button("") { copySelected() }.keyboardShortcut("c", modifiers: .command).hidden()
            Button("") { openSelected() }.keyboardShortcut("o", modifiers: .command).hidden()
            Button("") { archiveSelected() }.keyboardShortcut("a", modifiers: [.command, .shift]).hidden()
            Button("") { trashSelected() }.keyboardShortcut(.delete, modifiers: []).hidden()
            Button("") { previewSelected() }.keyboardShortcut(.space, modifiers: []).hidden()
            Button("") { editSelected() }.keyboardShortcut("e", modifiers: .command).hidden()
            Button("") { renameSelected() }.keyboardShortcut("r", modifiers: .command).hidden()
            Button("") { pinSelected() }.keyboardShortcut("p", modifiers: .command).hidden()
            Button("") { activateSearch() }.keyboardShortcut("f", modifiers: .command).hidden()
            ForEach(Array(items.prefix(9).enumerated()), id: \.element.id) { index, item in
                Button("") {
                    select(item, ignoringModifiers: true)
                    onUse(item, attachmentMap[item.id], .defaultPaste)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .hidden()
            }
        }
    }

    private func resizeHandle(currentHeight: CGFloat) -> some View {
        PanelResizeHandle(currentHeight: currentHeight, onResize: onResize)
    }

    private func feedbackPill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.thickMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28)))
            .shadow(radius: 10, y: 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 18)
            .accessibilityAddTraits(.isStaticText)
    }

    private func activateSearch(initialText: String = "") {
        session.acceptsPreviewShortcut = false
        searchActive = true
        if !initialText.isEmpty { query.append(initialText) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            searchFocused = true
        }
    }

    private func clearSearch() {
        query = ""
        typeFilter = nil
        sourceFilter = nil
        dateFilter = .anytime
        searchResultIDs = nil
        resolvedSearchToken = nil
    }

    private func handleEscape() {
        if popoverItemID != nil {
            popoverItemID = nil
            popoverKind = nil
        } else if searchActive && (hasFilters || !query.isEmpty) {
            clearSearch()
        } else if searchActive {
            searchFocused = false
            searchActive = false
            timelineFocused = true
        } else {
            onDismiss(true)
        }
    }

    private func handleTypedKey(_ press: KeyPress) -> KeyPress.Result {
        guard !searchFocused,
              press.modifiers.intersection([.command, .control, .option]).isEmpty,
              press.characters.count == 1,
              let scalar = press.characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else { return .ignored }
        activateSearch(initialText: press.characters)
        return .handled
    }

    private func select(_ item: StowItem, ignoringModifiers: Bool = false) {
        let flags = ignoringModifiers ? NSEvent.ModifierFlags() : NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
            selection = item.id
            selectionAnchor = item.id
        } else if flags.contains(.shift), let anchor = selectionAnchor,
                  let anchorIndex = items.firstIndex(where: { $0.id == anchor }),
                  let itemIndex = items.firstIndex(where: { $0.id == item.id }) {
            selectedIDs = Set(items[min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)].map(\.id))
            selection = item.id
        } else {
            selectedIDs = [item.id]
            selection = item.id
            selectionAnchor = item.id
        }
        searchFocused = false
        timelineFocused = true
        session.acceptsPreviewShortcut = true
    }

    private func moveSelection(by offset: Int, extending: Bool) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? 0
        let next = min(max(current + offset, 0), items.count - 1)
        let item = items[next]
        if extending {
            selectedIDs.insert(item.id)
            selection = item.id
        } else {
            select(item, ignoringModifiers: true)
        }
    }

    private func repairSelection() {
        let validIDs = Set(items.map(\.id))
        selectedIDs.formIntersection(validIDs)
        if let selection, validIDs.contains(selection) {
            if selectedIDs.isEmpty { selectedIDs = [selection] }
            return
        }
        selection = items.first?.id
        selectedIDs = selection.map { [$0] } ?? []
        selectionAnchor = selection
    }

    private var selectedItem: StowItem? { items.first { $0.id == selection } ?? items.first }

    private func performDefault() {
        guard let item = selectedItem else { return }
        onUse(item, attachments[item.id], .defaultPaste)
    }

    private func copySelected() {
        guard let item = selectedItem else { return }
        onUse(item, attachments[item.id], .copy)
    }

    private func openSelected() {
        guard let item = selectedItem, item.type == .link || item.type == .file else { return }
        onUse(item, attachments[item.id], .open)
    }

    private func archiveSelected() {
        for item in items where selectedIDs.contains(item.id) { appModel.archiveOrRestore(item) }
    }

    private func trashSelected() {
        for item in items where selectedIDs.contains(item.id) { appModel.trashOrRestore(item) }
    }

    private func pinSelected() {
        for item in items where selectedIDs.contains(item.id) { appModel.togglePin(item) }
    }

    private func previewSelected() {
        guard let item = selectedItem else { return }
        showPopover(.preview, for: item)
    }

    private func editSelected() {
        guard let item = selectedItem, item.type == .text || item.type == .code else { return }
        showPopover(.edit, for: item)
    }

    private func renameSelected() {
        guard let item = selectedItem else { return }
        showPopover(.rename, for: item)
    }

    private func showPopover(_ kind: RetrievalPopoverKind, for item: StowItem) {
        popoverKind = kind
        popoverItemID = item.id
    }

    private func popoverBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { popoverItemID == id },
            set: { presented in if !presented && popoverItemID == id { popoverItemID = nil; popoverKind = nil } }
        )
    }

    private func dragProvider(_ item: StowItem, attachment: StowAttachment?) -> NSItemProvider {
        let token = PanelDragSuccessToken { appModel.markUsed(item, metric: .itemDragged) }
        let provider = NSItemProvider()
        let payload = DragPayload(item: item, attachment: attachment)
        provider.suggestedName = payload.suggestedName
        provider.registerDataRepresentation(forTypeIdentifier: payload.typeIdentifier, visibility: .all) { completion in
            completion(payload.data, nil)
            token.record()
            return nil
        }
        return provider
    }

    private var hasFilters: Bool { typeFilter != nil || sourceFilter != nil || dateFilter != .anytime }

    private var attachmentToken: String {
        allAttachments.map { "\($0.id.uuidString):\($0.itemID.uuidString):\($0.byteCount)" }.joined(separator: "|")
    }

    private func rebuildAttachmentLookup() {
        attachmentLookup = Dictionary(allAttachments.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var searchToken: String {
        var hasher = Hasher()
        for item in allItems { hasher.combine(item.id); hasher.combine(item.updatedAt) }
        return [mode.rawValue, query, typeFilter?.rawValue ?? "", sourceFilter ?? "", dateFilter.rawValue, "\(hasher.finalize())"].joined(separator: "¦")
    }

    private func updateSearch() async {
        let requestedToken = searchToken
        guard !query.isEmpty || hasFilters else {
            searchResultIDs = nil
            resolvedSearchToken = nil
            return
        }
        let ids = await appModel.searchForRetrieval(
            items: allItems,
            text: query,
            type: typeFilter,
            source: sourceFilter,
            date: dateFilter,
            status: mode == .inbox ? .inbox : (mode == .archive ? .archived : nil)
        )
        guard !Task.isCancelled, requestedToken == searchToken else { return }
        searchResultIDs = ids
        resolvedSearchToken = requestedToken
    }

    private func localSearchIncludes(_ item: StowItem) -> Bool {
        guard typeFilter == nil || item.type == typeFilter,
              sourceFilter == nil || item.sourceApp == sourceFilter,
              dateFilter.includes(item.createdAt) else { return false }
        guard !query.isEmpty else { return true }
        return [item.title, item.textContent, item.urlString, item.sourceDomain, item.note, item.fileName]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func panelSort(_ lhs: StowItem, _ rhs: StowItem) -> Bool {
        if mode == .clipboard { return (lhs.lastUsedAt ?? lhs.createdAt) > (rhs.lastUsedAt ?? rhs.createdAt) }
        return lhs.createdAt > rhs.createdAt
    }
}

private struct PanelResizeHandle: View {
    let currentHeight: CGFloat
    let onResize: (CGFloat, Bool) -> Void
    @State private var initialHeight: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 7)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let start = initialHeight ?? currentHeight
                        if initialHeight == nil { initialHeight = start }
                        onResize(start - value.translation.height, false)
                    }
                    .onEnded { value in
                        let start = initialHeight ?? currentHeight
                        onResize(start - value.translation.height, true)
                        initialHeight = nil
                    }
            )
            .accessibilityLabel("Resize Stow Panel")
    }
}

private struct RetrievalPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct StowTimelineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: StowItem
    let attachment: StowAttachment?
    let isSelected: Bool
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            cardBody
        }
        .background(bodyBackground)
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 15 : 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 15 : 18, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.09), lineWidth: isSelected ? 4 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.20 : 0.11), radius: isSelected ? 12 : 7, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: isCompact ? 15 : 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.type.singularPanelName), \(item.title)")
        .accessibilityValue(item.sourceApp.map { "From \($0)" } ?? "Saved in Stow")
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.type.singularPanelName)
                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                Text(item.createdAt.panelRelativeLabel)
                    .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                    .opacity(0.78)
            }
            Spacer(minLength: 4)
            if let sourceIcon = SourceAppIconProvider.shared.icon(named: item.sourceApp) {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isCompact ? 25 : 34, height: isCompact ? 25 : 34)
                    .padding(isCompact ? 3 : 4)
                    .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: isCompact ? 8 : 11, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: item.type.icon)
                    .font(.system(size: isCompact ? 15 : 18, weight: .semibold))
                    .frame(width: isCompact ? 31 : 42, height: isCompact ? 31 : 42)
                    .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: isCompact ? 8 : 11, style: .continuous))
                    .foregroundStyle(item.type.panelColor)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(item.type == .file ? Color.primary : Color.white)
        .padding(.leading, isCompact ? 11 : 13)
        .padding(.trailing, isCompact ? 8 : 9)
        .frame(height: isCompact ? 39 : 51)
        .background(item.type.headerColor)
    }

    @ViewBuilder
    private var cardBody: some View {
        switch item.type {
        case .link: linkBody
        case .text: textBody
        case .code: codeBody
        case .image: imageBody
        case .file: fileBody
        }
    }

    private var linkBody: some View {
        VStack(spacing: 0) {
            if let image = linkPreviewImage {
                GeometryReader { proxy in
                    image.resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
            } else {
                ZStack {
                    LinearGradient(colors: [Color.blue.opacity(0.18), Color.cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "safari.fill")
                        .font(.system(size: isCompact ? 32 : 44))
                        .foregroundStyle(.blue.opacity(0.72))
                }
                .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: isCompact ? 12 : 14, weight: .semibold)).lineLimit(1)
                Text(item.sourceDomain ?? item.urlString ?? "Link").font(.system(size: isCompact ? 10 : 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, isCompact ? 10 : 12)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 42 : 51, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.textContent ?? item.title)
                .font(.system(size: isCompact ? 13 : 15, weight: .regular, design: .rounded))
                .lineSpacing(isCompact ? 1 : 3)
                .lineLimit(isCompact ? 5 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !isCompact {
                Text("\((item.textContent ?? "").count) characters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(isCompact ? 11 : 14)
        .foregroundStyle(Color.black.opacity(0.82))
        .background(Color(red: 1.0, green: 0.96, blue: 0.72))
    }

    private var codeBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(SimpleSyntaxHighlighter.highlight(item.textContent ?? item.title))
                .font(.system(size: isCompact ? 11 : 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(isCompact ? 11 : 14)
        }
        .background(Color(red: 0.105, green: 0.11, blue: 0.14))
    }

    private var imageBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                if let image = attachmentImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    LinearGradient(colors: [.pink.opacity(0.35), .purple.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "photo").font(.system(size: 42)).foregroundStyle(.white.opacity(0.8))
                }
                if !isCompact, let dimensions {
                    Text(dimensions)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.38), in: Capsule())
                        .padding(9)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var fileBody: some View {
        VStack(spacing: isCompact ? 7 : 10) {
            Spacer(minLength: 2)
            Image(nsImage: fileIcon)
                .resizable()
                .scaledToFit()
                .frame(width: isCompact ? 45 : 64, height: isCompact ? 45 : 64)
            Text(item.fileName ?? item.title)
                .font(.system(size: isCompact ? 11 : 13, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !isCompact {
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment?.byteCount ?? 0), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var bodyBackground: some ShapeStyle { Color(nsColor: .controlBackgroundColor) }

    private var linkPreviewImage: Image? {
        item.linkPreviewImageData.flatMap(NSImage.init(data:)).map(Image.init(nsImage:))
    }

    private var attachmentImage: Image? {
        guard let data = attachment?.thumbnailData ?? attachment?.data,
              let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
    }

    private var dimensions: String? {
        guard let width = attachment?.pixelWidth, let height = attachment?.pixelHeight else { return nil }
        return "\(width) × \(height)"
    }

    private var fileIcon: NSImage {
        if let attachment, let type = UTType(attachment.contentType) {
            return NSWorkspace.shared.icon(for: type)
        }
        let fileExtension = (item.fileName as NSString?)?.pathExtension ?? ""
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? .data)
    }
}

private struct RetrievalItemPopover: View {
    let item: StowItem
    let attachment: StowAttachment?
    let kind: RetrievalPopoverKind
    let onSave: (String, String?, String?, String?) -> Void
    let onCancel: () -> Void
    let onOpen: () -> Void

    @State private var title: String
    @State private var note: String
    @State private var text: String
    @State private var language: String

    init(
        item: StowItem,
        attachment: StowAttachment?,
        kind: RetrievalPopoverKind,
        onSave: @escaping (String, String?, String?, String?) -> Void,
        onCancel: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.item = item
        self.attachment = attachment
        self.kind = kind
        self.onSave = onSave
        self.onCancel = onCancel
        self.onOpen = onOpen
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note ?? "")
        _text = State(initialValue: item.textContent ?? "")
        _language = State(initialValue: item.language ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.borderless)
                Spacer()
                Text(popoverTitle).font(.headline)
                Spacer()
                if kind == .preview {
                    if item.type == .link || item.type == .file { Button("Open", action: onOpen).buttonStyle(.borderedProminent) }
                    else { Button("Done", action: onCancel).buttonStyle(.borderedProminent) }
                } else {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            Divider()
            if kind == .preview { preview }
            else { editor }
        }
        .frame(width: 520, height: kind == .rename ? 170 : 390)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }

    private var popoverTitle: String {
        switch kind { case .preview: "Preview"; case .edit: "Edit Item"; case .rename: "Rename" }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            if kind == .edit {
                TextEditor(text: $text)
                    .font(item.type == .code ? .system(.body, design: .monospaced) : .body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    TextField("Language", text: $language).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                    TextField("Note", text: $note).textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.title).font(.title2.bold())
                switch item.type {
                case .text:
                    Text(item.textContent ?? "").textSelection(.enabled)
                case .code:
                    Text(SimpleSyntaxHighlighter.highlight(item.textContent ?? "")).textSelection(.enabled)
                case .link:
                    Text(item.urlString ?? "").foregroundStyle(.blue).textSelection(.enabled)
                    if let description = item.linkDescription { Text(description).foregroundStyle(.secondary) }
                case .image:
                    if let data = attachment?.data, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                    }
                case .file:
                    Label(item.fileName ?? item.title, systemImage: "doc").font(.title3)
                    if let attachment { Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file)).foregroundStyle(.secondary) }
                }
                if let note = item.note, !note.isEmpty { Divider(); Text(note).foregroundStyle(.secondary) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            cleanTitle,
            note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            kind == .edit ? text : item.textContent,
            language.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

@MainActor
private final class SourceAppIconProvider {
    static let shared = SourceAppIconProvider()
    private var cache: [String: NSImage] = [:]
    private var missing: Set<String> = []

    func icon(named name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        if let image = cache[name] { return image }
        if missing.contains(name) { return nil }
        let runningURL = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
        let applicationURL = runningURL ?? installedApplicationURL(named: name)
        guard let applicationURL else { missing.insert(name); return nil }
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache[name] = image
        return image
    }

    private func installedApplicationURL(named name: String) -> URL? {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        let expected = name.hasSuffix(".app") ? name : "\(name).app"
        for root in roots {
            let candidate = root.appendingPathComponent(expected, isDirectory: true)
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

private final class PanelDragSuccessToken: @unchecked Sendable {
    private let success: @MainActor () -> Void
    init(success: @escaping @MainActor () -> Void) { self.success = success }
    nonisolated func record() { Task { @MainActor in success() } }
}

private extension ItemType {
    var singularPanelName: String {
        switch self { case .link: "Link"; case .text: "Text"; case .code: "Code"; case .image: "Image"; case .file: "File" }
    }

    var panelColor: Color {
        switch self { case .link: .blue; case .text: .yellow; case .code: .indigo; case .image: .red; case .file: .gray }
    }

    var headerColor: Color {
        switch self {
        case .link: Color(red: 0.18, green: 0.48, blue: 0.95)
        case .text: Color(red: 0.94, green: 0.68, blue: 0.13)
        case .code: Color(red: 0.28, green: 0.25, blue: 0.48)
        case .image: Color(red: 0.92, green: 0.28, blue: 0.30)
        case .file: Color(nsColor: .controlBackgroundColor)
        }
    }
}

private extension Date {
    var panelRelativeLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(self)))
        if seconds < 60 { return seconds < 10 ? "now" : "\(seconds) sec ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        if days < 30 { return "\(days) d ago" }
        let months = days / 30
        if months < 12 { return "\(months) mo ago" }
        return "\(months / 12) yr ago"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
