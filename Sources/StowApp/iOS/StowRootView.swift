import SwiftData
import SwiftUI
import StowCore

struct StowRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppModel.self) private var appModel
    @Query(sort: \StowItem.createdAt, order: .reverse) private var allItems: [StowItem]
    @State private var collectionLayout = ItemCollectionLayout.gallery
    @State private var showsFilters = false

    var body: some View {
        @Bindable var appModel = appModel
        Group {
            if horizontalSizeClass == .compact {
                compactNavigation
            } else {
                splitNavigation
            }
        }
        .searchable(text: $appModel.searchText, prompt: "Search saved content")
        .sheet(isPresented: $appModel.isAdding) { QuickAddView() }
        .sheet(isPresented: $showsFilters) { ItemFiltersView(availableSources: availableSources) }
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
    }

    private var compactNavigation: some View {
        NavigationStack {
            sectionContent
                .navigationTitle(appModel.selection.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        sectionsMenu
                    }
                    .compactLibraryBackground()
                    ToolbarItem(placement: .topBarLeading) {
                        Text(appModel.selection.rawValue)
                            .font(.title3.weight(.semibold))
                            .dynamicTypeSize(dynamicTypeSize)
                            .foregroundStyle(Color(uiColor: .label))
                            .fixedSize()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityShowsLargeContentViewer { Text(appModel.selection.rawValue) }
                            .accessibilityIdentifier("library-section-title")
                    }
                    .compactLibraryBackground()
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                    }
                    .compactLibraryBackground()
                    libraryActions
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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { libraryActions }
        } detail: {
            ContentUnavailableView("Choose an item", systemImage: "shippingbox", description: Text("Its contents and actions will appear here."))
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if appModel.selection == .settings {
            StowSettingsView()
        } else {
            ItemCollectionView(items: visibleItems, layout: collectionLayout)
        }
    }

    private var sectionsMenu: some View {
        Menu {
            ForEach(StowSection.allCases) { section in
                Button { appModel.selection = section } label: {
                    Label(section.rawValue, systemImage: section.icon)
                }
            }
        } label: {
            Label("Sections", systemImage: "line.3.horizontal")
                .labelStyle(.iconOnly)
                .foregroundStyle(.blue)
                .frame(minWidth: 44, minHeight: 44)
        }
        .tint(.blue)
        .accessibilityLabel("Sections")
        .accessibilityIdentifier("show-sections")
    }

    @ToolbarContentBuilder
    private var libraryActions: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if dynamicTypeSize.isAccessibilitySize && appModel.selection != .settings {
                Menu {
                    filterButton
                    layoutMenu
                    addButton
                } label: {
                    Label("Library actions", systemImage: "ellipsis")
                        .foregroundStyle(.blue)
                }
                .tint(.blue)
                .accessibilityIdentifier("library-actions")
            } else {
                if appModel.selection != .settings {
                    filterButton
                    layoutMenu
                }
                addButton
            }
        }
        .compactLibraryBackground()
    }

    private var filterButton: some View {
        Button { showsFilters = true } label: {
            Label("Filters", systemImage: activeFilterCount == 0 ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.blue)
        }
        .tint(.blue)
        .accessibilityIdentifier("show-filters")
        .accessibilityValue(activeFilterCount == 0 ? "No active filters" : "\(activeFilterCount) active filters")
    }

    private var layoutMenu: some View {
        Menu {
            Picker("View", selection: $collectionLayout) {
                ForEach(ItemCollectionLayout.allCases) { layout in
                    Label(layout.rawValue, systemImage: layout.icon).tag(layout)
                }
            }
        } label: {
            Label("View", systemImage: collectionLayout.icon).foregroundStyle(.blue)
        }
        .tint(.blue)
        .accessibilityIdentifier("collection-layout")
        .accessibilityValue(collectionLayout.rawValue)
    }

    private var addButton: some View {
        Button { showQuickAdd() } label: {
            Label("Add", systemImage: "plus").foregroundStyle(.blue)
        }
        .tint(.blue)
        .accessibilityIdentifier("add-item")
    }

    private var activeFilterCount: Int {
        (appModel.typeFilter == nil ? 0 : 1)
            + (appModel.sourceFilter == nil ? 0 : 1)
            + (appModel.dateFilter == .anytime ? 0 : 1)
    }

    private var visibleItems: [StowItem] {
        appModel.selection.sortedItems(allItems.filter { item in
            appModel.selection.includes(item) && (appModel.searchResultIDs?.contains(item.id) ?? true)
        })
    }

    private var availableSources: [String] {
        Array(Set(allItems.compactMap(\.sourceApp))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func showQuickAdd() {
        appModel.isAdding = true
    }

    private var searchToken: String {
        let itemRevision = SearchItemRevision(items: allItems)
        return [appModel.selection.rawValue, appModel.searchText, appModel.typeFilter?.rawValue ?? "", appModel.sourceFilter ?? "", appModel.dateFilter.rawValue, itemRevision.token].joined(separator: "¦")
    }

    private var privacyFooter: some View {
        Label(appModel.privacyStorageText, systemImage: appModel.privacyStorageText.contains("iCloud") ? "lock.icloud" : "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .accessibilityLabel(appModel.privacyStorageText)
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder
    func compactLibraryBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
