import SwiftUI
import StowCore

struct ItemFiltersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let availableSources: [String]

    var body: some View {
        @Bindable var appModel = appModel
        NavigationStack {
            Form {
                Picker("Type", selection: $appModel.typeFilter) {
                    Text("All types").tag(ItemType?.none)
                    ForEach(ItemType.allCases) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                }
                .accessibilityIdentifier("filter-type")
                Picker("Source", selection: $appModel.sourceFilter) {
                    Text("All sources").tag(String?.none)
                    ForEach(availableSources, id: \.self) { source in
                        Text(source).tag(Optional(source))
                    }
                }
                .accessibilityIdentifier("filter-source")
                Picker("Date added", selection: $appModel.dateFilter) {
                    ForEach(DateAddedFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .accessibilityIdentifier("filter-date")
            }
            .pickerStyle(.menu)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        appModel.typeFilter = nil
                        appModel.sourceFilter = nil
                        appModel.dateFilter = .anytime
                    }
                    .disabled(appModel.typeFilter == nil && appModel.sourceFilter == nil && appModel.dateFilter == .anytime)
                    .accessibilityIdentifier("reset-filters")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("dismiss-filters")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
