import Foundation
import Observation

struct AppAuthenticationAvailability {
    let method: String
    let unavailableReason: String?

    var isAvailable: Bool { unavailableReason == nil }
}

@MainActor
protocol AppAuthenticating: AnyObject {
    var availability: AppAuthenticationAvailability { get }
    /// Cancellation must invalidate this request without affecting a newer one.
    func authenticate(reason: String) async throws
    func invalidate()
}

/// Owns one scene's session. Authentication never survives a real background transition.
@MainActor
@Observable
final class AppLockController {
    enum Phase { case active, inactive, background }

    private(set) var isActive = false
    private(set) var isUnlocked: Bool
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?

    var isCovered: Bool { !isActive || (preferences.appLockEnabled && !isUnlocked) }
    var needsUnlock: Bool { preferences.appLockEnabled && !isUnlocked }
    var availability: AppAuthenticationAvailability { authenticator.availability }

    private let preferences: IOSPreferences
    private let authenticator: any AppAuthenticating
    private let now: () -> ContinuousClock.Instant
    private var backgroundedAt: ContinuousClock.Instant?
    private var configuration: Configuration
    private var generation = 0
    @ObservationIgnored private var authenticationTask: Task<Void, Never>?

    private struct Configuration: Equatable {
        let enabled: Bool
        let delay: IOSLockDelay
        let revision: Int
    }

    private enum Request {
        case unlock
        case enable
        case disable
        case delay(IOSLockDelay)

        var reason: String {
            switch self {
            case .unlock: "Unlock your Stow library."
            case .enable: "Enable App Lock for your Stow library."
            case .disable: "Turn off App Lock for your Stow library."
            case .delay: "Allow Stow to stay unlocked for longer."
            }
        }
    }

    init(
        preferences: IOSPreferences,
        authenticator: any AppAuthenticating,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.preferences = preferences
        self.authenticator = authenticator
        self.now = now
        configuration = Configuration(enabled: preferences.appLockEnabled, delay: preferences.lockDelay, revision: preferences.protectionRevision)
        isUnlocked = !preferences.appLockEnabled
    }

    deinit { authenticationTask?.cancel() }

    func transition(to phase: Phase) {
        synchronizePreferences()
        switch phase {
        case .active:
            if let backgroundedAt {
                if preferences.appLockEnabled,
                   backgroundedAt.duration(to: now()) >= .seconds(preferences.lockDelay.seconds) {
                    isUnlocked = false
                }
                self.backgroundedAt = nil
            }
            isActive = true
        case .inactive:
            // The system authentication prompt also makes a scene inactive. Do not cancel it.
            isActive = false
        case .background:
            isActive = false
            if backgroundedAt == nil { backgroundedAt = now() }
            cancelAuthentication()
            if preferences.appLockEnabled && preferences.lockDelay == .immediately {
                isUnlocked = false
            }
        }
    }

    /// Other scenes share preferences, but never share an authenticated session.
    func synchronizePreferences() {
        let current = currentConfiguration
        guard current != configuration else { return }
        cancelAuthentication()
        // A scene can miss an Off → On change while suspended. The revision still closes its session.
        isUnlocked = !current.enabled
        configuration = current
    }

    func unlock() {
        synchronizePreferences()
        guard needsUnlock else { return }
        begin(.unlock)
    }

    func setLockEnabled(_ enabled: Bool) {
        synchronizePreferences()
        guard enabled != preferences.appLockEnabled,
              !preferences.appLockEnabled || isUnlocked else { return }
        begin(enabled ? .enable : .disable)
    }

    func setLockDelay(_ delay: IOSLockDelay) {
        synchronizePreferences()
        guard isActive, !preferences.appLockEnabled || isUnlocked,
              delay != preferences.lockDelay else { return }
        if preferences.appLockEnabled && delay.seconds > preferences.lockDelay.seconds {
            begin(.delay(delay))
        } else {
            cancelAuthentication()
            preferences.commitLockDelay(delay)
            configuration = currentConfiguration
        }
    }

    func stop() {
        isActive = false
        isUnlocked = !preferences.appLockEnabled
        cancelAuthentication()
    }

    private var currentConfiguration: Configuration {
        Configuration(enabled: preferences.appLockEnabled, delay: preferences.lockDelay, revision: preferences.protectionRevision)
    }

    private func begin(_ request: Request) {
        guard isActive else { return }
        cancelAuthentication()
        errorMessage = nil
        if let reason = authenticator.availability.unavailableReason {
            errorMessage = reason
            return
        }
        isAuthenticating = true
        let token = generation
        let expectedConfiguration = configuration
        let authenticator = authenticator
        authenticationTask = Task { [weak self] in
            guard !Task.isCancelled,
                  self?.canStart(token: token, expected: expectedConfiguration) == true else {
                self?.finish(request, token: token, expected: expectedConfiguration, error: CancellationError())
                return
            }
            do {
                try await authenticator.authenticate(reason: request.reason)
                guard !Task.isCancelled else { return }
                self?.finish(request, token: token, expected: expectedConfiguration, error: nil)
            } catch {
                self?.finish(request, token: token, expected: expectedConfiguration, error: error)
            }
        }
    }

    private func canStart(token: Int, expected: Configuration) -> Bool {
        isActive && generation == token && currentConfiguration == expected
    }

    private func finish(_ request: Request, token: Int, expected: Configuration, error: Error?) {
        guard token == generation else { return }
        guard expected == currentConfiguration else {
            synchronizePreferences()
            return
        }
        authenticationTask = nil
        isAuthenticating = false
        if let error {
            errorMessage = "Authentication did not complete. \(error.localizedDescription) Try again or use your device passcode."
            return
        }
        switch request {
        case .unlock:
            isUnlocked = true
        case .enable:
            preferences.commitAppLock(enabled: true)
            isUnlocked = true
        case .disable:
            preferences.commitAppLock(enabled: false)
            isUnlocked = true
        case .delay(let delay):
            preferences.commitLockDelay(delay)
        }
        configuration = currentConfiguration
        errorMessage = nil
    }

    private func cancelAuthentication() {
        generation += 1
        authenticationTask?.cancel()
        authenticationTask = nil
        authenticator.invalidate()
        isAuthenticating = false
    }
}
