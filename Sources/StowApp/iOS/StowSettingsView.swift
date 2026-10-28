import Foundation
import SwiftData
import SwiftUI
import StowCore

struct StowSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(IOSPreferences.self) private var preferences
    @Environment(AppLockController.self) private var lock
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true
    @Query private var attachments: [StowAttachment]
    @State private var savesSharedItemsImmediately = StowShareSettings().savesSharedItemsImmediately

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            #if DEBUG
            if let milliseconds = model.launchReadyMilliseconds {
                Section("Diagnostics") {
                    LabeledContent("Launch readiness", value: String(format: "%.1f ms", milliseconds))
                        .accessibilityIdentifier("launch-readiness")
                }
            }
            #endif
            Section("Security & Privacy") {
                Toggle("App Lock", isOn: Binding(
                    get: { preferences.appLockEnabled },
                    set: { lock.setLockEnabled($0) }
                ))
                .disabled(lock.isAuthenticating)
                .accessibilityIdentifier("app-lock-enabled")
                Text("Protect this app with \(lock.availability.method). Your device passcode is also supported. App Lock does not add database encryption or stop iCloud sync.")
                    .font(.caption).foregroundStyle(.secondary)
                if preferences.appLockEnabled {
                    Picker("Lock after backgrounding", selection: Binding(
                        get: { preferences.lockDelay },
                        set: { lock.setLockDelay($0) }
                    )) {
                        ForEach(IOSLockDelay.allCases) { delay in Text(delay.title).tag(delay) }
                    }
                    .pickerStyle(.menu)
                    .disabled(lock.isAuthenticating)
                    .accessibilityIdentifier("lock-delay")
                    Text("A new launch always requires authentication. Turning off App Lock or choosing a longer interval requires authentication again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if lock.isAuthenticating {
                    ProgressView("Verifying identity…")
                } else if let message = lock.errorMessage ?? lock.availability.unavailableReason {
                    Label(message, systemImage: "exclamationmark.lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Automatic link previews", isOn: Binding(
                    get: { preferences.automaticLinkPreviewsEnabled },
                    set: { model.setAutomaticLinkPreviewsEnabled($0, preferences: preferences) }
                ))
                    .accessibilityIdentifier("automatic-link-previews")
                Text("When enabled, Stow fetches saved pages, including existing links without previews, and their icons and images. The page, redirect, and image hosts can receive requests. Turning this off stops new automatic requests on this device; it keeps existing previews, including those synced from other devices. Opening a link is unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Anonymous on-device product metrics", isOn: $analyticsEnabled)
                Text("Metrics never include saved content and never leave this device in v0.1.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Saving & Sharing") {
                Toggle("Save shared items immediately", isOn: $savesSharedItemsImmediately)
                    .accessibilityIdentifier("save-shared-items-immediately")
                Text("Skip the editable Save to Stow screen and save supported share-sheet content directly to Inbox. Turn this off to edit before saving. Sharing can add items while Stow is locked, but cannot browse your library.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance & Browsing") {
                Picker("Launch page", selection: $preferences.launchPage) {
                    ForEach(IOSLaunchPage.allCases) { page in Text(page.title).tag(page) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("launch-page")
                Text("Used when a scene starts, not when you return to an open app. Last Library Section excludes Settings and Trash.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(IOSAppearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("appearance")
                Text("These preferences stay on this device. The Share Extension follows the system appearance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sync & Data") {
                LabeledContent("Account", value: model.usesPrivateICloud ? "Private iCloud" : "Local only")
                    .accessibilityIdentifier("sync-account")
                LabeledContent("Status", value: model.syncStatus.title)
                    .accessibilityIdentifier("sync-status")
                if let guidance = model.syncStatus.guidance {
                    Label(guidance, systemImage: "exclamationmark.icloud")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Stow remains available offline and synchronizes when iCloud reconnects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Attachments", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                    .accessibilityIdentifier("attachment-usage")
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
