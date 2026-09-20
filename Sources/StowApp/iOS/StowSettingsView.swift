import Foundation
import SwiftData
import SwiftUI
import StowCore

struct StowSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true
    @Query private var attachments: [StowAttachment]
    @State private var savesSharedItemsImmediately = StowShareSettings().savesSharedItemsImmediately

    var body: some View {
        Form {
            #if DEBUG
            if let milliseconds = model.launchReadyMilliseconds {
                Section("Diagnostics") {
                    LabeledContent("Launch readiness", value: String(format: "%.1f ms", milliseconds))
                        .accessibilityIdentifier("launch-readiness")
                }
            }
            #endif
            Section("Sharing") {
                Toggle("Save shared items immediately", isOn: $savesSharedItemsImmediately)
                    .accessibilityIdentifier("save-shared-items-immediately")
                Text("Skip the editable Save to Stow screen and save supported share-sheet content directly to Inbox. Turn this off when you want to edit the title, note, or other options before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Toggle("Anonymous on-device product metrics", isOn: $analyticsEnabled)
                Text("Metrics never include saved content and never leave this device in v0.1.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sync") {
                LabeledContent("Account", value: model.usesPrivateICloud ? "Private iCloud" : "Local only")
                LabeledContent("Status", value: model.syncStatus.title)
                if let guidance = model.syncStatus.guidance {
                    Label(guidance, systemImage: "exclamationmark.icloud")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Stow remains available offline and synchronizes when iCloud reconnects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Storage") {
                LabeledContent("Attachments", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                if storageBytes > 10 * 1_024 * 1_024 * 1_024 {
                    Label("Stow attachments exceed 10 GB. Review large files if device storage is constrained.", systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                Text("Trash is permanently deleted after 30 days. Source attachments are never silently evicted.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: analyticsEnabled) { _, enabled in model.setMetricsEnabled(enabled) }
        .onChange(of: savesSharedItemsImmediately) { _, enabled in
            StowShareSettings().savesSharedItemsImmediately = enabled
        }
    }

    private var storageBytes: Int64 {
        attachments.reduce(0) { $0 + Int64($1.byteCount) }
    }
}
