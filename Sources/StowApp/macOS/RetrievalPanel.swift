import AppKit
import SwiftData
import SwiftUI
import StowCore

@MainActor
final class RetrievalPanelController {
    private var panel: NSPanel?

    func present(model: AppModel, container: ModelContainer) {
        if panel == nil {
            let root = RetrievalPanelView()
                .environment(model)
                .modelContainer(container)
            let hosting = NSHostingController(rootView: root)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 430),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Stow Quick Panel"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            panel.contentViewController = hosting
            panel.center()
            self.panel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct RetrievalPanelView: View {
    @Environment(AppModel.self) private var appModel
    @Query private var allItems: [StowItem]
    @Query private var allAttachments: [StowAttachment]
    @State private var query = ""
    @State private var filter: ItemType?
    @State private var selection: UUID?

    private var items: [StowItem] {
        allItems.filter { item in
            item.status != .trashed && (filter == nil || item.type == filter) && (query.isEmpty || [item.title, item.textContent, item.urlString, item.note, item.fileName].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) })
        }
        .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shippingbox.fill").foregroundStyle(.tint)
                TextField("Search Stow", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .onSubmit { performDefault() }
                Picker("Type", selection: $filter) {
                    Text("All").tag(ItemType?.none)
                    ForEach(ItemType.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                .frame(width: 120)
            }
            .padding()
            Divider()
            if items.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try another search or type filter."))
            } else {
                List(items, selection: $selection) { item in
                    StowPanelRow(item: item).tag(item.id)
                }
                .onAppear { selection = items.first?.id }
                .onChange(of: items.map(\.id)) { _, ids in if !ids.contains(selection ?? UUID()) { selection = ids.first } }
            }
            Divider()
            HStack {
                shortcut("↩", "Use")
                shortcut("⌘C", "Copy")
                shortcut("⌘O", "Open")
                shortcut("⌘⇧A", "Archive")
                shortcut("⌫", "Trash")
                Spacer()
            }
            .padding(10)
        }
        .frame(minWidth: 620, minHeight: 360)
        .background(.regularMaterial)
        .overlay {
            Button("") { copySelected() }.keyboardShortcut("c").hidden()
            Button("") { openSelected() }.keyboardShortcut("o").hidden()
            Button("") { archiveSelected() }.keyboardShortcut("a", modifiers: [.command, .shift]).hidden()
            Button("") { trashSelected() }.keyboardShortcut(.delete, modifiers: []).hidden()
        }
    }

    private var selected: StowItem? { items.first { $0.id == selection } ?? items.first }

    private func performDefault() {
        guard let item = selected else { return }
        switch item.type {
        case .link, .file:
            appModel.performUse(item, action: .open, metric: .itemOpened) { try PlatformActions.open(item, attachment: attachment(for: item)) }
        case .text, .code, .image:
            appModel.performUse(item, action: .copy, metric: .itemCopied) { try PlatformActions.copy(item, attachmentData: attachment(for: item)?.data) }
        }
    }
    private func copySelected() { guard let item = selected else { return }; appModel.performUse(item, action: .copy, metric: .itemCopied) { try PlatformActions.copy(item, attachmentData: attachment(for: item)?.data) } }
    private func openSelected() { guard let item = selected else { return }; appModel.performUse(item, action: .open, metric: .itemOpened) { try PlatformActions.open(item, attachment: attachment(for: item)) } }
    private func attachment(for item: StowItem) -> StowAttachment? { allAttachments.first { $0.itemID == item.id } }
    private func archiveSelected() { guard let item = selected else { return }; appModel.archiveOrRestore(item) }
    private func trashSelected() { guard let item = selected else { return }; appModel.trashOrRestore(item) }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        HStack(spacing: 4) { Text(keys).padding(.horizontal, 5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4)); Text(action) }
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct StowPanelRow: View {
    let item: StowItem
    var body: some View {
        HStack {
            Image(systemName: item.type.icon).foregroundStyle(item.type.tint).frame(width: 24)
            VStack(alignment: .leading) {
                Text(item.title).fontWeight(.medium).lineLimit(1)
                Text(item.previewText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(item.lastUsedAt ?? item.createdAt, style: .relative).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
