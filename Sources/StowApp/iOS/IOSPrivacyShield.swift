import SwiftUI
import UIKit

/// A separate opaque window covers native sheets as well as the SwiftUI library.
/// The content window stays mounted, so locking does not discard editor drafts.
struct IOSPrivacyShield: UIViewRepresentable {
    let lock: AppLockController
    let appearance: IOSAppearance
    let isCovered: Bool
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(lock: lock) }

    func makeUIView(context: Context) -> WindowAnchorView {
        let view = WindowAnchorView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ view: WindowAnchorView, context: Context) {
        context.coordinator.update(appearance: appearance)
        if let window = view.window { context.coordinator.attach(to: window) }
    }

    static func dismantleUIView(_ view: WindowAnchorView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.detach()
    }

    final class WindowAnchorView: UIView {
        var onWindowChange: ((UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindowChange?(window) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private let lock: AppLockController
        private weak var contentWindow: UIWindow?
        private var shieldWindow: UIWindow?
        private var originalAlpha: CGFloat = 1
        private var originalAccessibilityHidden = false
        private var originalInteractionEnabled = true
        private var appearance: IOSAppearance = .system

        init(lock: AppLockController) { self.lock = lock }

        deinit { NotificationCenter.default.removeObserver(self) }

        func attach(to window: UIWindow) {
            guard contentWindow !== window, let scene = window.windowScene else { return }
            detach()
            contentWindow = window
            originalAlpha = window.alpha
            originalAccessibilityHidden = window.accessibilityElementsHidden
            originalInteractionEnabled = window.isUserInteractionEnabled
            let shield = UIWindow(windowScene: scene)
            shield.windowLevel = .alert + 1
            shield.rootViewController = UIHostingController(rootView: AppLockScreen(lock: lock))
            shieldWindow = shield

            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(willDeactivate), name: UIScene.willDeactivateNotification, object: scene)
            center.addObserver(self, selector: #selector(didEnterBackground), name: UIScene.didEnterBackgroundNotification, object: scene)
            center.addObserver(self, selector: #selector(willEnterForeground), name: UIScene.willEnterForegroundNotification, object: scene)
            center.addObserver(self, selector: #selector(didActivate), name: UIScene.didActivateNotification, object: scene)
            switch scene.activationState {
            case .foregroundActive: lock.transition(to: .active)
            case .background: lock.transition(to: .background)
            default: lock.transition(to: .inactive)
            }
            update(appearance: appearance)
        }

        func update(appearance: IOSAppearance) {
            self.appearance = appearance
            guard let contentWindow, let shieldWindow else { return }
            shieldWindow.overrideUserInterfaceStyle = appearance.interfaceStyle
            if lock.isCovered {
                contentWindow.endEditing(true)
                // Hiding the source also protects snapshots if the system omits the shield window.
                contentWindow.alpha = 0
                contentWindow.accessibilityElementsHidden = true
                contentWindow.isUserInteractionEnabled = false
                shieldWindow.isHidden = false
                if lock.isActive && !shieldWindow.isKeyWindow { shieldWindow.makeKeyAndVisible() }
            } else {
                let restoreKey = shieldWindow.isKeyWindow
                shieldWindow.isHidden = true
                contentWindow.alpha = originalAlpha
                contentWindow.accessibilityElementsHidden = originalAccessibilityHidden
                contentWindow.isUserInteractionEnabled = originalInteractionEnabled
                if restoreKey { contentWindow.makeKey() }
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            if contentWindow != nil { lock.stop() }
            shieldWindow?.isHidden = true
            shieldWindow = nil
            contentWindow?.alpha = originalAlpha
            contentWindow?.accessibilityElementsHidden = originalAccessibilityHidden
            contentWindow?.isUserInteractionEnabled = originalInteractionEnabled
            contentWindow = nil
        }

        @objc private func willDeactivate() {
            lock.transition(to: .inactive)
            update(appearance: appearance)
        }

        @objc private func didEnterBackground() {
            lock.transition(to: .background)
            update(appearance: appearance)
        }

        @objc private func willEnterForeground() {
            lock.transition(to: .inactive)
            update(appearance: appearance)
        }

        @objc private func didActivate() {
            lock.transition(to: .active)
            update(appearance: appearance)
        }
    }
}

private struct AppLockScreen: View {
    let lock: AppLockController

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(lock.needsUnlock ? "Stow is locked" : "Stow is private")
                    .font(.title2.bold())
                if lock.isAuthenticating {
                    ProgressView("Verifying identity…")
                } else if lock.needsUnlock {
                    Text("Use \(lock.availability.method) or your device passcode to open your library.")
                    if let message = lock.errorMessage ?? lock.availability.unavailableReason {
                        Text(message).foregroundStyle(.secondary)
                    }
                    Button("Unlock Stow") { lock.unlock() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!lock.isActive)
                        .accessibilityIdentifier("unlock-stow")
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 500)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .accessibilityIdentifier("privacy-shield")
    }
}

extension IOSAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
