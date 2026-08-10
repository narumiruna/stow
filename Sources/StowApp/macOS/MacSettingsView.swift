import AppKit
import ApplicationServices
import StowCore
import SwiftData
import SwiftUI

struct MacSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true
    @AppStorage("clipboardMonitoringEnabled") private var clipboardMonitoringEnabled = true
    @Query private var attachments: [StowAttachment]

    @State private var directPasteGranted = AXIsProcessTrusted()
    @State private var shortcutDraft: MacShortcutConfiguration
    @State private var appliedShortcuts: MacShortcutConfiguration
    @State private var shortcutFeedback: MacShortcutApplyResult?
    @State private var isApplyingShortcuts = false

    private let applyShortcuts: MacShortcutApplyHandler

    init(applyShortcuts: @escaping MacShortcutApplyHandler) {
        let configuration = MacShortcutConfiguration.current()
        _shortcutDraft = State(initialValue: configuration)
        _appliedShortcuts = State(initialValue: configuration)
        self.applyShortcuts = applyShortcuts
    }

    var body: some View {
        TabView {
            capturePage
                .tabItem { Label(MacSettingsPage.capture.rawValue, systemImage: MacSettingsPage.capture.systemImage) }
                .accessibilityIdentifier("settings-capture-page")
            pasteAndShortcutsPage
                .tabItem { Label(MacSettingsPage.pasteAndShortcuts.rawValue, systemImage: MacSettingsPage.pasteAndShortcuts.systemImage) }
                .accessibilityIdentifier("settings-paste-shortcuts-page")
            syncAndStoragePage
                .tabItem { Label(MacSettingsPage.syncAndStorage.rawValue, systemImage: MacSettingsPage.syncAndStorage.systemImage) }
                .accessibilityIdentifier("settings-sync-storage-page")
            privacyPage
                .tabItem { Label(MacSettingsPage.privacy.rawValue, systemImage: MacSettingsPage.privacy.systemImage) }
                .accessibilityIdentifier("settings-privacy-page")
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 440, idealHeight: 500)
        .onAppear { refreshPermissionStatuses() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshPermissionStatuses() }
        }
        .onChange(of: analyticsEnabled) { _, enabled in model.setMetricsEnabled(enabled) }
        .onChange(of: clipboardMonitoringEnabled) { _, _ in
            NotificationCenter.default.post(name: .stowClipboardMonitoringChanged, object: nil)
            refreshClipboardStatus()
        }
        #if DEBUG
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-testing-force-dark") ? .dark : nil)
        .background(MacSettingsWindowConfigurator())
        #endif
    }

    private var capturePage: some View {
        settingsPage(title: "Capture", subtitle: "Choose what Stow saves from the clipboard.") {
            settingsGroup("Clipboard Monitoring") {
                Toggle("Automatically save copied items", isOn: $clipboardMonitoringEnabled)
                    .accessibilityIdentifier("settings-clipboard-monitoring-toggle")
                statusRow(title: "Access", value: displayedClipboardMonitoringStatus)
                guidance("While Stow is running, new text, links, images, and files copied to the clipboard are saved to Inbox. Clipboard contents that existed before monitoring started are ignored.")
                if #available(macOS 15.4, *) {
                    guidance("For reliable background capture, set Stow to Always Allow in Privacy & Security › Paste from Other Apps.")
                    Button("Open Privacy & Security…") { openPrivacySettings() }
                        .accessibilityIdentifier("settings-open-paste-privacy")
                }
            }
        }
    }

    private var pasteAndShortcutsPage: some View {
        settingsPage(title: "Paste & Shortcuts", subtitle: "Control direct paste and the shortcuts that open Stow.") {
            settingsGroup("Direct Paste") {
                statusRow(title: "Accessibility", value: directPasteGranted ? "Granted" : "Copy-only fallback")
                guidance("Accessibility lets Stow paste the selected item back into the app you were using. Without it, Stow safely copies the item so you can press Command-V yourself.")
                if directPasteGranted {
                    Button("Open Accessibility Settings…") { openAccessibilitySettings() }
                } else {
                    Button("Request Accessibility Access…") { requestAccessibilityAccess() }
                        .accessibilityIdentifier("settings-request-accessibility")
                    guidance("Stow only asks macOS for this permission when you choose the button above.")
                }
            }

            settingsGroup("Keyboard Shortcuts") {
                statusRow(title: "Global registration", value: displayedGlobalShortcutStatus)
                    .accessibilityIdentifier("settings-global-shortcut-status")
                Picker("Quick Add", selection: $shortcutDraft.quickAdd) {
                    Text("⌥⇧S").tag("optionShiftS")
                    Text("⌃⌥S").tag("controlOptionS")
                    Text("⌘⌥S").tag("commandOptionS")
                }
                .accessibilityIdentifier("settings-quick-add-shortcut")
                Picker("Quick Panel", selection: $shortcutDraft.quickPanel) {
                    Text("⌘⇧V").tag("commandShiftV")
                    Text("⌥⌘V").tag("optionCommandV")
                    Text("⌃⇧V").tag("controlShiftV")
                }
                .accessibilityIdentifier("settings-quick-panel-shortcut")
                guidance("If another app owns a shortcut, Stow reports the conflict here. Your current shortcuts should remain available until a replacement configuration succeeds.")

                HStack {
                    Button("Apply Shortcuts") { applyShortcutDraft() }
                        .disabled(shortcutDraft == appliedShortcuts || isApplyingShortcuts)
                        .accessibilityIdentifier("settings-apply-shortcuts")
                    if isApplyingShortcuts {
                        ProgressView().controlSize(.small)
                        Text("Applying…").foregroundStyle(.secondary)
                    }
                }
                if let shortcutFeedback {
                    switch shortcutFeedback {
                    case .success:
                        feedback("Shortcuts updated.", systemImage: "checkmark.circle.fill", color: .green)
                    case .failure(let message):
                        feedback(message, systemImage: "exclamationmark.triangle.fill", color: .orange)
                            .accessibilityIdentifier("settings-shortcut-feedback")
                    }
                }
            }
        }
    }

    private var syncAndStoragePage: some View {
        settingsPage(title: "Sync & Storage", subtitle: "Review where your library is stored and recover local search.") {
            settingsGroup("Sync") {
                statusRow(title: "Account", value: model.usesPrivateICloud ? "Private iCloud" : "Local only")
                statusRow(title: "Status", value: model.syncStatus.title)
                if let guidanceText = model.syncStatus.guidance {
                    feedback(guidanceText, systemImage: "exclamationmark.icloud", color: .orange)
                    Button("Open iCloud Settings…") { openICloudSettings() }
                        .accessibilityIdentifier("settings-open-icloud")
                } else {
                    guidance("Stow remains available offline and synchronizes when iCloud reconnects.")
                }
            }

            settingsGroup("Storage") {
                statusRow(title: "Attachments", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                if storageBytes > 10 * 1_024 * 1_024 * 1_024 {
                    feedback("Stow attachments exceed 10 GB. Review large files if device storage is constrained.", systemImage: "externaldrive.badge.exclamationmark", color: .orange)
                }
                guidance("Trash is permanently deleted after 30 days. Source attachments are never silently evicted.")
            }

            settingsGroup("Search Index") {
                guidance("If Library search is missing items or reports an index error, rebuild its local index. Your saved items are not changed.")
                searchIndexRecoveryControls
            }
        }
    }

    private var privacyPage: some View {
        settingsPage(title: "Privacy", subtitle: "Keep product diagnostics on this Mac under your control.") {
            settingsGroup("On-device Metrics") {
                Toggle("Anonymous on-device product metrics", isOn: $analyticsEnabled)
                    .accessibilityIdentifier("settings-analytics-toggle")
                guidance("Metrics never include saved content and never leave this device in v0.1.")
            }
            #if DEBUG
            if let milliseconds = model.launchReadyMilliseconds {
                settingsGroup("Diagnostics") {
                    statusRow(title: "Launch readiness", value: String(format: "%.1f ms", milliseconds))
                        .accessibilityIdentifier("launch-readiness")
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var searchIndexRecoveryControls: some View {
        switch model.searchIndexRebuildState {
        case .idle:
            Button("Rebuild Search Index") { rebuildSearchIndex() }
                .accessibilityIdentifier("settings-rebuild-search-index")
        case .inProgress:
            HStack {
                ProgressView().controlSize(.small)
                Text("Rebuilding search index…")
            }
            .accessibilityIdentifier("settings-search-index-progress")
        case .succeeded(let documentCount):
            feedback("Search index rebuilt for \(documentCount) item\(documentCount == 1 ? "" : "s").", systemImage: "checkmark.circle.fill", color: .green)
            HStack {
                Button("Rebuild Again") { rebuildSearchIndex() }
                Button("Dismiss") { model.dismissSearchIndexRebuildFeedback() }
            }
        case .failed(let message):
            feedback("The search index could not be rebuilt. Your previous index remains available. \(message)", systemImage: "exclamationmark.triangle.fill", color: .orange)
                .accessibilityIdentifier("settings-search-index-error")
            HStack {
                Button("Try Again") { rebuildSearchIndex() }
                Button("Dismiss") { model.dismissSearchIndexRebuildFeedback() }
            }
        }
    }

    private func settingsPage<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2).fontWeight(.semibold)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            Text(title).font(.headline)
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline).fontWeight(.medium)
            Text(value)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guidance(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedback(_ text: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.callout)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyShortcutDraft() {
        guard shortcutDraft != appliedShortcuts, !isApplyingShortcuts else { return }
        isApplyingShortcuts = true
        shortcutFeedback = nil
        let candidate = shortcutDraft
        Task {
            let result = await applyShortcuts(candidate)
            isApplyingShortcuts = false
            shortcutFeedback = result
            if result == .success {
                appliedShortcuts = candidate
            } else {
                shortcutDraft = appliedShortcuts
            }
        }
    }

    private func rebuildSearchIndex() {
        Task { await model.rebuildSearchIndex() }
    }

    private func refreshPermissionStatuses() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-settings-accessibility-denied") {
            directPasteGranted = false
        } else {
            directPasteGranted = AXIsProcessTrusted()
        }
        #else
        directPasteGranted = AXIsProcessTrusted()
        #endif
        refreshClipboardStatus()
    }

    private func refreshClipboardStatus() {
        guard clipboardMonitoringEnabled else {
            model.clipboardMonitoringStatus = "Off"
            return
        }
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .default: model.clipboardMonitoringStatus = "Permission not requested"
            case .ask: model.clipboardMonitoringStatus = "Needs Always Allow"
            case .alwaysAllow: model.clipboardMonitoringStatus = "Always Allow"
            case .alwaysDeny: model.clipboardMonitoringStatus = "Blocked by macOS"
            @unknown default: model.clipboardMonitoringStatus = "Unknown"
            }
        }
    }

    private func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        directPasteGranted = AXIsProcessTrustedWithOptions(options)
    }

    private func openPrivacySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security")
    }

    private func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openICloudSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private var displayedClipboardMonitoringStatus: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-settings-long-status") {
            return "Clipboard access needs attention in System Settings before automatic background capture can resume reliably."
        }
        #endif
        return model.clipboardMonitoringStatus
    }

    private var displayedGlobalShortcutStatus: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-settings-long-status") {
            return "The selected shortcut is already used by another application; the previous working shortcuts remain registered until a replacement succeeds."
        }
        #endif
        return model.globalShortcutStatus
    }

    private var storageBytes: Int64 {
        attachments.reduce(0) { $0 + Int64($1.byteCount) }
    }
}

#if DEBUG
private struct MacSettingsWindowConfigurator: NSViewRepresentable {
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
        window.identifier = NSUserInterfaceItemIdentifier("stow-settings-window")
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-testing-settings-size=") }) else { return }
        let rawSize = argument.replacingOccurrences(of: "--ui-testing-settings-size=", with: "")
        let components = rawSize.split(separator: "x").compactMap { Double($0) }
        guard components.count == 2 else { return }
        let size = NSSize(width: max(620, components[0]), height: max(440, components[1]))
        guard window.contentLayoutRect.size != size else { return }
        window.setContentSize(size)
        window.center()
    }
}
#endif
