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
        .sheet(isPresented: $appModel.isAdding) { QuickAddView() }
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
                        Button { appModel.isAdding = true } label: { Label("Add", systemImage: "plus") }
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
                        Button { appModel.isAdding = true } label: { Label("Add", systemImage: "plus") }
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
