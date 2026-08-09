import SwiftData
import SwiftUI
import StowCore

struct StowRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppModel.self) private var appModel
    @Query(sort: \StowItem.createdAt, order: .reverse) private var allItems: [StowItem]

    var body: some View {
        @Bindable var appModel = appModel
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactNavigation
            } else {
                splitNavigation
            }
            #else
            splitNavigation
            #endif
        }
        .searchable(text: $appModel.searchText, prompt: "Search saved content")
        .stowQuickAddSheet(isPresented: $appModel.isAdding)
        .alert("Stow couldn't complete that action", isPresented: Binding(
            get: { appModel.presentedError != nil },
            set: { if !$0 { appModel.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { appModel.presentedError = nil }
        } message: { Text(appModel.presentedError ?? "Unknown error") }
        .onAppear { appModel.markLaunchReady() }
        .task { appModel.connect(modelContext) }
        .task(id: searchToken) { await appModel.updateSearch(items: allItems) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { appModel.runMaintenance() } }
        .privacySensitive()
        #if DEBUG && os(macOS)
        .overlay(alignment: .topTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-drop-target") {
                PanelDropTestTarget()
                    .padding(24)
            }
        }
        #endif
        #if os(iOS)
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(.regularMaterial).ignoresSafeArea()
                    Label("Stow is private", systemImage: "lock.fill").font(.title2.bold())
                }
                .accessibilityHidden(true)
            }
        }
        #endif
    }

    private var compactNavigation: some View {
        NavigationStack {
            sectionContent
                .navigationTitle(appModel.selection.rawValue)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Menu {
                            ForEach(StowSection.allCases) { section in
                                Button { appModel.selection = section } label: {
                                    Label(section.rawValue, systemImage: section.icon)
                                }
                            }
                        } label: {
                            Label("Sections", systemImage: "sidebar.left")
                        }
                        .accessibilityIdentifier("show-sections")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { showQuickAdd() } label: { Label("Add", systemImage: "plus") }
                            .accessibilityIdentifier("add-item")
                    }
                }
        }
    }

    private var splitNavigation: some View {
        NavigationSplitView {
            List(selection: Binding<StowSection?>(
                get: { appModel.selection },
                set: { if let section = $0 { appModel.selection = section } }
            )) {
                ForEach(StowSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationTitle("Stow")
            .safeAreaInset(edge: .bottom) { privacyFooter }
        } content: {
            sectionContent
                .navigationTitle(appModel.selection.rawValue)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showQuickAdd() } label: { Label("Add", systemImage: "plus") }
                            .accessibilityIdentifier("add-item")
                    }
                }
        } detail: {
            ContentUnavailableView("Choose an item", systemImage: "shippingbox", description: Text("Its contents and actions will appear here."))
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if appModel.selection == .settings {
            StowSettingsView()
        } else {
            ItemCollectionView(items: visibleItems, availableSources: availableSources)
        }
    }

    private var visibleItems: [StowItem] {
        allItems.filter { item in
            sectionIncludes(item) && (appModel.searchResultIDs?.contains(item.id) ?? true)
        }
        .sorted(by: sectionSort)
    }

    private var availableSources: [String] {
        Array(Set(allItems.compactMap(\.sourceApp))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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

    private func showQuickAdd() {
        #if os(macOS)
        NotificationCenter.default.post(name: .stowShowQuickAdd, object: nil)
        #else
        appModel.isAdding = true
        #endif
    }

    private var searchToken: String {
        var versionHasher = Hasher()
        for item in allItems { versionHasher.combine(item.id); versionHasher.combine(item.updatedAt) }
        let itemVersion = "\(allItems.count):\(versionHasher.finalize())"
        return [appModel.selection.rawValue, appModel.searchText, appModel.typeFilter?.rawValue ?? "", appModel.sourceFilter ?? "", appModel.dateFilter.rawValue, itemVersion].joined(separator: "¦")
    }

    private func sectionSort(_ lhs: StowItem, _ rhs: StowItem) -> Bool {
        if appModel.selection == .recent { return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast) }
        return lhs.createdAt > rhs.createdAt
    }

    private var privacyFooter: some View {
        Label(appModel.privacyStorageText, systemImage: appModel.privacyStorageText.contains("iCloud") ? "lock.icloud" : "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .accessibilityLabel(appModel.privacyStorageText)
    }
}

#if DEBUG && os(macOS)
private struct PanelDropTestTarget: View {
    @State private var accepted = false

    var body: some View {
        Text(accepted ? "Drop accepted" : "Panel drop target")
            .font(.headline)
            .padding(.horizontal, 24)
            .frame(width: 260, height: 120)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [6])))
            .dropDestination(for: String.self) { values, _ in
                guard !values.isEmpty else { return false }
                accepted = true
                return true
            }
            .accessibilityIdentifier("panel-drop-target")
    }
}
#endif

private extension View {
    @ViewBuilder
    func stowQuickAddSheet(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        sheet(isPresented: isPresented) { QuickAddView() }
        #else
        self
        #endif
    }
}
