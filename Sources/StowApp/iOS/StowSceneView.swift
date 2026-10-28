import SwiftUI

struct StowSceneView: View {
    let model: AppModel
    let preferences: IOSPreferences
    @State private var lock: AppLockController
    @State private var appliedLaunchPage = false

    init(model: AppModel, preferences: IOSPreferences) {
        self.model = model
        self.preferences = preferences
        _lock = State(initialValue: AppLockController(
            preferences: preferences,
            authenticator: DeviceOwnerAuthenticator()
        ))
    }

    var body: some View {
        StowRootView()
            .environment(model)
            .environment(preferences)
            .environment(lock)
            .preferredColorScheme(preferences.appearance.colorScheme)
            // Cover the first frame, before the UIKit window anchor is attached.
            .opacity(lock.isCovered ? 0 : 1)
            .allowsHitTesting(!lock.isCovered)
            .accessibilityHidden(lock.isCovered)
            .background {
                IOSPrivacyShield(
                    lock: lock,
                    appearance: preferences.appearance,
                    isCovered: lock.isCovered,
                    isActive: lock.isActive
                )
            }
            .onAppear {
                guard !appliedLaunchPage else { return }
                appliedLaunchPage = true
                model.selection = preferences.initialSection
            }
            .onChange(of: model.selection) { _, section in
                preferences.recordLibrarySection(section)
            }
            .onChange(of: preferences.protectionRevision) { _, _ in lock.synchronizePreferences() }
    }
}
