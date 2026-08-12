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

private enum RetrievalSearchPhase: Equatable {
    case idle
    case loading
    case ready
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
private final class RetrievalEditorDirtyState {
    var isDirty = false
}

private struct PanelActionFeedback: Identifiable {
    let id = UUID()
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
}

struct RetrievalPanelView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \StowItem.createdAt, order: .reverse) private var allItems: [StowItem]
    @Query private var allAttachments: [StowAttachment]
    @ObservedObject var session: RetrievalPanelSession

    let onRequestClose: (QuickPanelCloseRequest) -> Void
    let onApproveClose: (UUID) -> Void
    let onCancelClose: (UUID) -> Void
    let onRegisterSettingsAction: (QuickPanelSettingsAction) -> Void
    let onResize: (CGFloat, Bool) -> Void
    let onUse: (StowItem, StowAttachment?, RetrievalUseKind) -> Void

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
    @State private var editorDirtyState = RetrievalEditorDirtyState()
    @State private var editorErrorMessage: String?
    @State private var pendingDiscardScope: QuickPanelDiscardScope?
    @State private var pendingDiscardCommandID: UUID?
    @State private var monitoringEnabled = UserDefaults.standard.object(forKey: "clipboardMonitoringEnabled") == nil || UserDefaults.standard.bool(forKey: "clipboardMonitoringEnabled")
    @State private var attachmentLookup: [UUID: StowAttachment] = [:]
    @State private var searchPhase: RetrievalSearchPhase = .idle
    @State private var searchRetryGeneration = 0
    @State private var actionFeedback: PanelActionFeedback?
    @State private var panelMenuPresented = false
    @FocusState private var searchFocused: Bool
    @FocusState private var timelineFocused: Bool

    private var isCompact: Bool { session.panelHeight < 275 }
    private var isNarrow: Bool { session.panelWidth < 700 }

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
                } else if let actionFeedback {
                    feedbackPill(actionFeedback)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if case .failed(let message) = searchPhase {
                    searchFailureBanner(message)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, isCompact ? 52 : 62)
                } else if popoverItemID == nil, let message = appModel.presentedError {
                    actionErrorBanner(message)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, isCompact ? 52 : 62)
                }
                if panelMenuPresented { panelMenuOverlay }
                popoverOverlay(availableSize: geometry.size)
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
            .task(id: searchTaskToken) { await updateSearch() }
            .task(id: actionFeedback?.id) { await expireActionFeedback() }
            .onAppear {
                onRegisterSettingsAction(QuickPanelSettingsAction { openSettings() })
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
            .onChange(of: session.closeCommand?.id) { _, _ in handleCloseCommand() }
            .onChange(of: searchFocused) { _, focused in
                session.acceptsPreviewShortcut = !focused && popoverItemID == nil
            }
            .onDisappear { session.isDragging = false }
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
    }

    private var toolbar: some View {
        HStack(spacing: isCompact ? 7 : 10) {
            if searchActive {
                searchBar
                    .layoutPriority(1)
                modePickerMenu
                statusIndicators(compact: true)
                panelMenu
                closeButton
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: isCompact ? 7 : 10) {
                        searchButton
                        ForEach(RetrievalPanelMode.allCases.filter { $0 != .archive }) { toolbarMode in
                            modeChip(toolbarMode)
                        }
                        Spacer(minLength: 4)
                        statusIndicators(compact: false)
                        quickAddButton
                        panelMenu
                        closeButton
                    }
                    HStack(spacing: 7) {
                        searchButton
                        modePickerMenu
                        Spacer(minLength: 2)
                        statusIndicators(compact: true)
                        panelMenu
                        closeButton
                    }
                }
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .frame(height: isCompact ? 48 : 58)
        .background(.ultraThinMaterial.opacity(0.42))
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var searchButton: some View {
        Button { activateSearch() } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityIdentifier("panel-search")
    }

    private var quickAddButton: some View {
        Button { onRequestClose(.destination(.quickAdd)) } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick Add")
    }

    private var closeButton: some View {
        Button { onRequestClose(.explicit) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Close Quick Panel (Esc)")
        .accessibilityLabel("Close Quick Panel")
        .accessibilityHint("Returns focus to the app you were using")
        .accessibilityIdentifier("panel-close")
    }

    private func statusIndicators(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Label(
                RetrievalPastePresentation.statusLabel(
                    directAvailable: session.directPasteAvailable,
                    compact: compact
                ),
                systemImage: session.directPasteAvailable ? "arrow.right.doc.on.clipboard" : "doc.on.doc"
            )
            .accessibilityLabel(
                RetrievalPastePresentation.statusAccessibilityLabel(
                    directAvailable: session.directPasteAvailable
                )
            )
            if !monitoringEnabled {
                Label(compact ? "Paused" : "Monitoring paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Clipboard monitoring paused")
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, compact ? 7 : 9)
        .frame(height: 28)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel-status")
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            if isNarrow, activeFilterCount > 0 {
                Label("\(activeFilterCount) filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("\(activeFilterCount) search filters applied")
            } else {
                if let typeFilter {
                    filterToken(typeFilter.singularPanelName, color: typeFilter.panelColor) { self.typeFilter = nil }
                }
                if let sourceFilter {
                    filterToken(sourceFilter, color: .blue) { self.sourceFilter = nil }
                }
                if dateFilter != .anytime {
                    filterToken(dateFilter.rawValue, color: .orange) { dateFilter = .anytime }
                }
            }
            searchTextField
            if searchPhase == .loading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
                    .accessibilityIdentifier("panel-clear-search")
            }
            filterMenu
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: 760)
        .frame(height: isCompact ? 36 : 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(searchFocused ? 0.9 : 0.35), lineWidth: searchFocused ? 2 : 1))
    }

    private var searchTextField: some View {
        TextField("Search Stow", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: isCompact ? 14 : 16, weight: .medium))
            .focused($searchFocused)
            .disabled(popoverItemID != nil)
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
    }

    private var activeFilterCount: Int {
        (typeFilter == nil ? 0 : 1) + (sourceFilter == nil ? 0 : 1) + (dateFilter == .anytime ? 0 : 1)
    }

    private var modePickerMenu: some View {
        Menu {
            ForEach(RetrievalPanelMode.allCases.filter { $0 != .archive }) { toolbarMode in
                Button { mode = toolbarMode } label: {
                    Label(toolbarMode.rawValue, systemImage: toolbarMode.icon)
                }
            }
        } label: {
            Label(mode.rawValue, systemImage: mode.icon)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(.regularMaterial, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Collection: \(mode.rawValue)")
        .accessibilityIdentifier("panel-active-mode")
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
        Button { panelMenuPresented.toggle() } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .onChange(of: monitoringEnabled) { _, enabled in
            UserDefaults.standard.set(enabled, forKey: "clipboardMonitoringEnabled")
            NotificationCenter.default.post(name: .stowClipboardMonitoringChanged, object: nil)
        }
    }

    private var panelMenuOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { panelMenuPresented = false }
            VStack(alignment: .leading, spacing: 2) {
                panelMenuButton("Archive", systemImage: "archivebox") { mode = .archive }
                panelMenuButton("Quick Add", systemImage: "plus") { onRequestClose(.destination(.quickAdd)) }
                panelMenuButton("Open Library", systemImage: "macwindow") { onRequestClose(.destination(.library)) }
                panelMenuButton("Settings", systemImage: "gear") { onRequestClose(.destination(.settings)) }
                Divider().padding(.vertical, 3)
                Toggle("Monitor Clipboard", isOn: $monitoringEnabled)
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                Divider().padding(.vertical, 3)
                panelMenuButton("Close Quick Panel", systemImage: "xmark") { onRequestClose(.explicit) }
            }
            .padding(7)
            .frame(width: 194)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.35)))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .padding(.top, isCompact ? 44 : 52)
            .padding(.trailing, 42)
        }
    }

    private func panelMenuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            panelMenuPresented = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    Image(systemName: hasActiveSearch ? "magnifyingglass" : mode.icon)
                        .font(.system(size: isCompact ? 25 : 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(hasActiveSearch ? "No Results" : "Nothing in \(mode.rawValue)")
                        .font(.headline)
                    Text(emptyStateMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if hasActiveSearch {
                        Button("Clear Search and Filters") { clearSearch() }
                            .buttonStyle(.bordered)
                    } else if mode == .archive {
                        Button("Open Library") { onRequestClose(.destination(.library)) }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Quick Add") { onRequestClose(.destination(.quickAdd)) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
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
        return PanelCardDragSource(
            content: AnyView(
                StowTimelineCard(
                    item: item,
                    attachment: attachment,
                    isSelected: selected,
                    isCompact: isCompact
                )
                .frame(width: isCompact ? 176 : 224, height: max(128, availableHeight - (isCompact ? 21 : 28)))
            ),
            accessibilityLabel: "\(item.type.singularPanelName), \(item.title)",
            accessibilityIdentifier: "panel-item-\(item.id.uuidString)",
            material: { dragMaterial(item, attachment: attachment) },
            onSelect: { select(item) },
            onDoubleClick: {
                select(item, ignoringModifiers: true)
                performDefault(item)
            },
            onDragStateChanged: { session.isDragging = $0 },
            onDragCompleted: {
                appModel.markUsed(item, metric: .itemDragged)
                onRequestClose(.completedUse)
            }
        )
        .contextMenu { cardContextMenu(item, attachment: attachment) }
    }

    @ViewBuilder
    private func popoverOverlay(availableSize: CGSize) -> some View {
        if let item = allItems.first(where: { $0.id == popoverItemID }), let popoverKind {
            ZStack {
                Color.black.opacity(0.16)
                    .contentShape(Rectangle())
                    .onTapGesture { onRequestClose(.outsideClick) }
                RetrievalItemPopover(
                    item: item,
                    attachment: attachments[item.id],
                    kind: popoverKind,
                    errorMessage: editorErrorMessage,
                    discardScope: pendingDiscardScope,
                    availableSize: availableSize,
                    onSave: { title, note, text, language in
                        if let message = appModel.saveForPanel(item, title: title, note: note, text: text, language: language) {
                            editorErrorMessage = message
                            return false
                        }
                        editorErrorMessage = nil
                        closePopover()
                        return true
                    },
                    onCancel: { closePopover() },
                    onOpen: { onUse(item, attachments[item.id], .open) },
                    onDirtyChange: { editorDirtyState.isDirty = $0 },
                    onDismissError: { editorErrorMessage = nil },
                    onConfirmDiscard: { confirmDiscard() },
                    onKeepEditing: { cancelDiscard() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func cardContextMenu(_ item: StowItem, attachment: StowAttachment?) -> some View {
        Button { performDefault(item) } label: { Label("Use", systemImage: "return") }
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
        Button { togglePin(item) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") }
        Button { archiveOrRestore(item) } label: { Label(item.status == .archived ? "Restore to Inbox" : "Archive", systemImage: "archivebox") }
        Button(role: .destructive) { moveToTrash(item) } label: { Label("Move to Trash", systemImage: "trash") }
    }

    private var keyboardCommands: some View {
        ZStack {
            Button("") { onRequestClose(.escape) }.keyboardShortcut(.cancelAction).hidden()
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
                    performDefault(item)
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

    private func feedbackPill(_ feedback: PanelActionFeedback) -> some View {
        HStack(spacing: 10) {
            Text(feedback.message)
            if let actionTitle = feedback.actionTitle, let action = feedback.action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .fontWeight(.bold)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.28)))
        .shadow(radius: 10, y: 4)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
        .accessibilityElement(children: .contain)
    }

    private func actionErrorBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Button("Dismiss") { appModel.presentedError = nil }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.orange.opacity(0.45)))
        .accessibilityElement(children: .contain)
    }

    private func searchFailureBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Search unavailable — showing local matches")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Button("Retry") { searchRetryGeneration += 1 }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
            Button { searchPhase = .idle } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss search error")
        }
        .help(message)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(.thickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.orange.opacity(0.45)))
        .accessibilityElement(children: .contain)
    }

    private func showActionFeedback(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        actionFeedback = PanelActionFeedback(message: message, actionTitle: actionTitle, action: action)
    }

    private func expireActionFeedback() async {
        guard let id = actionFeedback?.id else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled, actionFeedback?.id == id else { return }
        actionFeedback = nil
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

    private func handleCloseCommand() {
        guard let command = session.closeCommand else { return }
        let layer: QuickPanelPresentedLayer
        if panelMenuPresented {
            layer = .menu
        } else if popoverItemID == nil {
            layer = .none
        } else if popoverKind == .preview {
            layer = .preview
        } else {
            layer = .editor(isDirty: editorDirtyState.isDirty)
        }
        let state = QuickPanelCloseState(
            searchIsActive: searchActive,
            hasSearchCriteria: hasActiveSearch,
            presentedLayer: layer
        )
        switch QuickPanelClosePolicy.decision(for: command.request, state: state) {
        case .closePanel:
            onApproveClose(command.id)
        case .closePresentedLayer:
            if panelMenuPresented { panelMenuPresented = false }
            else { closePopover() }
            onCancelClose(command.id)
        case .clearSearch:
            clearSearch()
            onCancelClose(command.id)
        case .collapseSearch:
            searchFocused = false
            searchActive = false
            timelineFocused = true
            onCancelClose(command.id)
        case .confirmDiscard(let scope):
            pendingDiscardCommandID = command.id
            pendingDiscardScope = scope
        }
    }

    private func confirmDiscard() {
        guard let scope = pendingDiscardScope, let commandID = pendingDiscardCommandID else { return }
        pendingDiscardScope = nil
        pendingDiscardCommandID = nil
        closePopover()
        switch scope {
        case .layerOnly:
            onCancelClose(commandID)
        case .panel:
            onApproveClose(commandID)
        }
    }

    private func cancelDiscard() {
        guard let commandID = pendingDiscardCommandID else {
            pendingDiscardScope = nil
            return
        }
        pendingDiscardScope = nil
        pendingDiscardCommandID = nil
        onCancelClose(commandID)
    }

    private func handleTypedKey(_ press: KeyPress) -> KeyPress.Result {
        guard popoverItemID == nil, !searchFocused else { return .ignored }
        var modifiers: QuickPanelInputModifiers = []
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
        switch QuickPanelInputPolicy.decision(characters: press.characters, modifiers: modifiers) {
        case .beginSearch(let initialText):
            activateSearch(initialText: initialText)
            return .handled
        case .ignored:
            return .ignored
        }
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
        let state = QuickPanelSelectionPolicy.repair(
            QuickPanelSelectionState(
                selection: selection,
                selectedIDs: selectedIDs,
                selectionAnchor: selectionAnchor
            ),
            visibleIDs: items.map(\.id)
        )
        selection = state.selection
        selectedIDs = state.selectedIDs
        selectionAnchor = state.selectionAnchor
    }

    private var selectedItem: StowItem? {
        let visibleIDs = items.map(\.id)
        guard let id = QuickPanelSelectionPolicy.actionableSelection(
            in: QuickPanelSelectionState(
                selection: selection,
                selectedIDs: selectedIDs,
                selectionAnchor: selectionAnchor
            ),
            visibleIDs: visibleIDs
        ) else { return nil }
        return items.first { $0.id == id }
    }

    private func performDefault(_ requestedItem: StowItem? = nil) {
        let item = requestedItem.flatMap { requested in items.first { $0.id == requested.id } } ?? selectedItem
        guard let item else { return }
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
        let selected = items.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty, appModel.archiveOrRestore(selected) else { return }
        let restored = selected.allSatisfy { $0.status == .inbox }
        showActionFeedback(restored ? "Restored to Inbox" : "Archived")
    }

    private func trashSelected() {
        let selected = items.filter { selectedIDs.contains($0.id) }
        let ids = selected.map(\.id)
        guard !ids.isEmpty, appModel.moveToTrash(selected) else { return }
        showActionFeedback(ids.count == 1 ? "Moved to Trash" : "Moved \(ids.count) items to Trash", actionTitle: "Undo") {
            if appModel.restoreFromTrash(ids: ids) {
                showActionFeedback(ids.count == 1 ? "Restored from Trash" : "Restored \(ids.count) items")
            }
        }
    }

    private func pinSelected() {
        let selected = items.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty, appModel.togglePin(selected) else { return }
        showActionFeedback(selected.allSatisfy(\.isPinned) ? "Pinned" : "Unpinned")
    }

    private func togglePin(_ item: StowItem) {
        guard appModel.togglePin(item) else { return }
        showActionFeedback(item.isPinned ? "Pinned" : "Unpinned")
    }

    private func archiveOrRestore(_ item: StowItem) {
        guard appModel.archiveOrRestore(item) else { return }
        showActionFeedback(item.status == .inbox ? "Restored to Inbox" : "Archived")
    }

    private func moveToTrash(_ item: StowItem) {
        let id = item.id
        guard appModel.moveToTrash([item]) else { return }
        showActionFeedback("Moved to Trash", actionTitle: "Undo") {
            if appModel.restoreFromTrash(ids: [id]) { showActionFeedback("Restored from Trash") }
        }
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
        session.acceptsPreviewShortcut = false
        searchFocused = false
        timelineFocused = false
        editorErrorMessage = nil
        editorDirtyState.isDirty = false
        popoverKind = kind
        popoverItemID = item.id
    }

    private func closePopover() {
        popoverItemID = nil
        popoverKind = nil
        editorDirtyState.isDirty = false
        editorErrorMessage = nil
        session.acceptsPreviewShortcut = true
        if searchActive {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                searchFocused = true
            }
        } else {
            timelineFocused = true
        }
    }

    private func dragMaterial(_ item: StowItem, attachment: StowAttachment?) -> PanelDragMaterial? {
        switch item.type {
        case .text, .code:
            let value = item.textContent ?? item.title
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(value, forType: .string)
            if let rtf = try? NSAttributedString(string: value).data(
                from: NSRange(location: 0, length: (value as NSString).length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                pasteboardItem.setData(rtf, forType: .rtf)
            }
            return PanelDragMaterial(writer: pasteboardItem)
        case .link:
            guard let value = item.urlString, let url = URL(string: value) else { return nil }
            return PanelDragMaterial(writer: url as NSURL)
        case .image:
            guard let data = attachment?.data, let image = NSImage(data: data) else { return nil }
            return PanelDragMaterial(writer: image)
        case .file:
            guard let data = attachment?.data else { return nil }
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("StowTransfers", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let rawName = ((item.fileName ?? item.title) as NSString).lastPathComponent
                let name = rawName.isEmpty || rawName == "." || rawName == ".." ? "Stow Item" : rawName
                let fileURL = directory.appendingPathComponent(name)
                try data.write(to: fileURL, options: .atomic)
                return PanelDragMaterial(writer: fileURL as NSURL, cleanupDirectory: directory)
            } catch {
                appModel.presentedError = "The item could not be prepared for dragging. \(error.localizedDescription)"
                return nil
            }
        }
    }

    private var hasFilters: Bool { typeFilter != nil || sourceFilter != nil || dateFilter != .anytime }
    private var hasActiveSearch: Bool { !query.isEmpty || hasFilters }

    private var emptyStateMessage: String {
        if hasActiveSearch { return "Try a different search or remove a filter." }
        switch mode {
        case .clipboard: return "Copied items will appear here while clipboard monitoring is on."
        case .inbox: return "New captures that need attention will appear here."
        case .pinned: return "Pin an item to keep it easy to reach."
        case .archive: return "Archived items remain available in your Library."
        }
    }

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

    private var searchTaskToken: String { "\(searchToken)¦retry:\(searchRetryGeneration)" }

    private func updateSearch() async {
        let requestedToken = searchToken
        guard hasActiveSearch else {
            searchResultIDs = nil
            resolvedSearchToken = nil
            searchPhase = .idle
            return
        }
        searchPhase = .loading
        let outcome = await appModel.searchForRetrieval(
            items: allItems,
            text: query,
            type: typeFilter,
            source: sourceFilter,
            date: dateFilter,
            status: mode == .inbox ? .inbox : (mode == .archive ? .archived : nil)
        )
        guard !Task.isCancelled, requestedToken == searchToken else { return }
        switch outcome {
        case .success(let ids):
            searchResultIDs = ids
            resolvedSearchToken = requestedToken
            searchPhase = .ready
        case .failure(let message):
            searchPhase = .failed(message)
        }
    }

    private func localSearchIncludes(_ item: StowItem) -> Bool {
        guard typeFilter == nil || item.type == typeFilter,
              sourceFilter == nil || item.sourceApp == sourceFilter,
              dateFilter.includes(item.createdAt) else { return false }
        guard !query.isEmpty else { return true }
        let normalizedQuery = query.panelSearchNormalized
        return [item.title, item.textContent, item.urlString, item.sourceDomain, item.note, item.fileName]
            .compactMap { $0 }
            .contains { $0.panelSearchNormalized.localizedCaseInsensitiveContains(normalizedQuery) }
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
    let errorMessage: String?
    let discardScope: QuickPanelDiscardScope?
    let availableSize: CGSize
    let onSave: (String, String?, String?, String?) -> Bool
    let onCancel: () -> Void
    let onOpen: () -> Void
    let onDirtyChange: (Bool) -> Void
    let onDismissError: () -> Void
    let onConfirmDiscard: () -> Void
    let onKeepEditing: () -> Void

    private let originalTitle: String
    private let originalNote: String
    private let originalText: String
    private let originalLanguage: String

    @State private var title: String
    @State private var note: String
    @State private var text: String
    @State private var language: String
    @FocusState private var titleFocused: Bool
    @FocusState private var confirmationFocused: Bool

    init(
        item: StowItem,
        attachment: StowAttachment?,
        kind: RetrievalPopoverKind,
        errorMessage: String?,
        discardScope: QuickPanelDiscardScope?,
        availableSize: CGSize,
        onSave: @escaping (String, String?, String?, String?) -> Bool,
        onCancel: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onDirtyChange: @escaping (Bool) -> Void,
        onDismissError: @escaping () -> Void,
        onConfirmDiscard: @escaping () -> Void,
        onKeepEditing: @escaping () -> Void
    ) {
        self.item = item
        self.attachment = attachment
        self.kind = kind
        self.errorMessage = errorMessage
        self.discardScope = discardScope
        self.availableSize = availableSize
        self.onSave = onSave
        self.onCancel = onCancel
        self.onOpen = onOpen
        self.onDirtyChange = onDirtyChange
        self.onDismissError = onDismissError
        self.onConfirmDiscard = onConfirmDiscard
        self.onKeepEditing = onKeepEditing
        originalTitle = item.title
        originalNote = item.note ?? ""
        originalText = item.textContent ?? ""
        originalLanguage = item.language ?? ""
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note ?? "")
        _text = State(initialValue: item.textContent ?? "")
        _language = State(initialValue: item.language ?? "")
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    if kind == .preview {
                        if item.type == .link || item.type == .file {
                            Button("Done", action: onCancel).buttonStyle(.borderless)
                        } else {
                            Color.clear.frame(width: 36, height: 1)
                        }
                    } else {
                        Button("Cancel", action: onCancel).buttonStyle(.borderless)
                    }
                    Spacer()
                    Text(popoverTitle).font(.headline)
                    Spacer()
                    if kind == .preview {
                        if item.type == .link || item.type == .file {
                            Button("Open", action: onOpen).buttonStyle(.borderedProminent)
                        } else {
                            Button("Done", action: onCancel).buttonStyle(.borderedProminent)
                        }
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
            if discardScope != nil { discardConfirmation }
        }
        .frame(
            width: min(520, max(320, availableSize.width - 32)),
            height: kind == .rename
                ? min(errorMessage == nil ? 170 : 220, max(160, availableSize.height - 24))
                : max(176, availableSize.height - 28)
        )
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .onAppear {
            onDirtyChange(isDirty)
            if discardScope != nil { confirmationFocused = true }
            else if kind != .preview { titleFocused = true }
        }
        .onChange(of: title) { _, _ in onDirtyChange(isDirty) }
        .onChange(of: text) { _, _ in onDirtyChange(isDirty) }
        .onChange(of: language) { _, _ in onDirtyChange(isDirty) }
        .onChange(of: note) { _, _ in onDirtyChange(isDirty) }
        .onChange(of: discardScope != nil) { _, isPresented in
            if isPresented { confirmationFocused = true }
            else if kind != .preview { titleFocused = true }
        }
    }

    private var discardConfirmation: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Discard unsaved changes?")
                    .font(.headline)
                Text("Your saved item will remain unchanged.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Keep Editing", action: onKeepEditing)
                        .keyboardShortcut(.cancelAction)
                        .focused($confirmationFocused)
                        .accessibilityIdentifier("panel-keep-editing")
                    Button(closesPanelAfterDiscard ? "Discard Changes and Close" : "Discard Changes", role: .destructive, action: onConfirmDiscard)
                        .accessibilityIdentifier("panel-confirm-discard")
                }
            }
            .padding(22)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.3)))
            .shadow(radius: 18, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discard unsaved changes?")
    }

    private var closesPanelAfterDiscard: Bool {
        guard let discardScope else { return false }
        if case .panel = discardScope { return true }
        return false
    }

    private var popoverTitle: String {
        switch kind { case .preview: "Preview"; case .edit: "Edit Item"; case .rename: "Rename" }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("panel-editor-error")
                    Button("Dismiss", action: onDismissError).buttonStyle(.borderless)
                }
                .accessibilityElement(children: .contain)
            }
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .accessibilityIdentifier("panel-editor-title")
            if kind == .edit {
                TextEditor(text: $text)
                    .font(item.type == .code ? .system(.body, design: .monospaced) : .body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityIdentifier("panel-editor-content")
                HStack {
                    TextField("Language", text: $language)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                    TextField("Note", text: $note)
                        .textFieldStyle(.roundedBorder)
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

    private var isDirty: Bool {
        title != originalTitle || note != originalNote || text != originalText || language != originalLanguage
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = onSave(
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

private struct PanelDragMaterial {
    let writer: any NSPasteboardWriting
    let cleanupDirectory: URL?

    init(writer: any NSPasteboardWriting, cleanupDirectory: URL? = nil) {
        self.writer = writer
        self.cleanupDirectory = cleanupDirectory
    }
}

private struct PanelCardDragSource: NSViewRepresentable {
    let content: AnyView
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let material: () -> PanelDragMaterial?
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onDragStateChanged: (Bool) -> Void
    let onDragCompleted: () -> Void

    func makeNSView(context: Context) -> PanelCardDragSourceView {
        let view = PanelCardDragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: PanelCardDragSourceView, context: Context) { update(nsView) }

    private func update(_ view: PanelCardDragSourceView) {
        view.hostingView.rootView = content
        view.invalidateIntrinsicContentSize()
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        view.material = material
        view.onSelect = onSelect
        view.onDoubleClick = onDoubleClick
        view.onDragStateChanged = onDragStateChanged
        view.onDragCompleted = onDragCompleted
    }
}

@MainActor
private final class PanelCardDragSourceView: NSView, NSDraggingSource {
    let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    var material: (() -> PanelDragMaterial?)?
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    var onDragCompleted: (() -> Void)?
    private var cleanupDirectory: URL?
    private var dragStarted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return nil
        default:
            return bounds.contains(point) ? self : nil
        }
    }

    override var intrinsicContentSize: NSSize { hostingView.fittingSize }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let material = material?() else { return }
        dragStarted = true
        onDragStateChanged?(true)
        cleanupDirectory = material.cleanupDirectory
        let item = NSDraggingItem(pasteboardWriter: material.writer)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: location.x - 32, y: location.y - 32, width: 64, height: 64), contents: dragImage())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard !dragStarted, event.clickCount >= 2 else { return }
        onDoubleClick?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let directory = cleanupDirectory
        cleanupDirectory = nil
        dragStarted = false
        onDragStateChanged?(false)
        if operation != [] {
            if let directory {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(60))
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            onDragCompleted?()
        } else if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func dragImage() -> NSImage {
        NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Stow item") ?? NSImage()
    }
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
    var panelSearchNormalized: String { applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? self }
}
