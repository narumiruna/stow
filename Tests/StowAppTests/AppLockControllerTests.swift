import XCTest
@testable import StowApp

@MainActor
final class AppLockControllerTests: XCTestCase {
    func testColdLockedSceneRequiresAuthenticationEvenWithGracePeriod() throws {
        let scene = try Scene(locked: true, delay: .fiveMinutes)
        defer { scene.cleanup() }
        XCTAssertTrue(scene.lock.isCovered)
        scene.lock.transition(to: .active)
        XCTAssertTrue(scene.lock.needsUnlock)
        XCTAssertFalse(scene.lock.isUnlocked)
        XCTAssertEqual(scene.auth.reasons.count, 0, "Cold launch must not start a prompt loop")
    }

    func testDisabledLockStillCoversInactiveScenes() throws {
        let scene = try Scene()
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        XCTAssertFalse(scene.lock.isCovered)
        scene.lock.transition(to: .inactive)
        XCTAssertTrue(scene.lock.isCovered)
        scene.lock.transition(to: .active)
        XCTAssertFalse(scene.lock.isCovered)
    }

    func testEnablePersistsOnlyAfterSuccessfulAuthentication() async throws {
        let scene = try Scene()
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        scene.lock.setLockEnabled(true)
        await scene.auth.waitForRequests(1)
        XCTAssertFalse(scene.preferences.appLockEnabled)
        XCTAssertTrue(scene.lock.isAuthenticating)
        scene.auth.succeed(0)
        await settle()
        XCTAssertTrue(scene.preferences.appLockEnabled)
        XCTAssertTrue(scene.lock.isUnlocked)
        XCTAssertFalse(scene.lock.isCovered)
        XCTAssertTrue(IOSPreferences(defaults: scene.defaults).appLockEnabled)
    }

    func testUnavailableAuthenticationDoesNotEnableLock() throws {
        let scene = try Scene()
        defer { scene.cleanup() }
        scene.auth.availability = AppAuthenticationAvailability(method: "Device Passcode", unavailableReason: "Set up a passcode.")
        scene.lock.transition(to: .active)
        scene.lock.setLockEnabled(true)
        XCTAssertFalse(scene.preferences.appLockEnabled)
        XCTAssertFalse(scene.lock.isAuthenticating)
        XCTAssertEqual(scene.lock.errorMessage, "Set up a passcode.")
        XCTAssertTrue(scene.auth.reasons.isEmpty)
    }

    func testCancelledEnableKeepsPreviousSettingAndCanRetry() async throws {
        let scene = try Scene()
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        scene.lock.setLockEnabled(true)
        await scene.auth.waitForRequests(1)
        scene.auth.fail(0)
        await waitUntil { !scene.lock.isAuthenticating }
        XCTAssertFalse(scene.preferences.appLockEnabled)
        XCTAssertNotNil(scene.lock.errorMessage)
        scene.lock.setLockEnabled(true)
        await scene.auth.waitForRequests(2)
        scene.auth.succeed(1)
        await settle()
        XCTAssertTrue(scene.preferences.appLockEnabled)
        XCTAssertNil(scene.lock.errorMessage)
    }

    func testDisableRequiresFreshAuthenticationEvenInUnlockedScene() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        await unlock(scene)
        scene.lock.setLockEnabled(false)
        await scene.auth.waitForRequests(2)
        XCTAssertTrue(scene.preferences.appLockEnabled)
        scene.auth.fail(1)
        await settle()
        XCTAssertTrue(scene.preferences.appLockEnabled)
        scene.lock.setLockEnabled(false)
        await scene.auth.waitForRequests(3)
        scene.auth.succeed(2)
        await settle()
        XCTAssertFalse(scene.preferences.appLockEnabled)
        XCTAssertTrue(scene.lock.isUnlocked)
    }

    func testLongerGraceRequiresAuthenticationButShorterGraceDoesNot() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        await unlock(scene)
        scene.lock.setLockDelay(.fiveMinutes)
        await scene.auth.waitForRequests(2)
        XCTAssertEqual(scene.preferences.lockDelay, .immediately)
        scene.auth.fail(1)
        await settle()
        XCTAssertEqual(scene.preferences.lockDelay, .immediately)
        scene.lock.setLockDelay(.oneMinute)
        await scene.auth.waitForRequests(3)
        scene.auth.succeed(2)
        await settle()
        XCTAssertEqual(scene.preferences.lockDelay, .oneMinute)
        scene.lock.setLockDelay(.immediately)
        XCTAssertEqual(scene.preferences.lockDelay, .immediately)
        XCTAssertEqual(scene.auth.reasons.count, 3)
    }

    func testImmediateBackgroundRequiresUnlockOnReturn() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        await unlock(scene)
        scene.lock.transition(to: .inactive)
        scene.lock.transition(to: .background)
        scene.lock.transition(to: .active)
        XCTAssertTrue(scene.lock.isCovered)
        XCTAssertTrue(scene.lock.needsUnlock)
    }

    func testGracePeriodsUseContinuousTimeAndExactExpiryBoundary() async throws {
        for delay in [IOSLockDelay.oneMinute, .fiveMinutes] {
            let scene = try Scene(locked: true, delay: delay)
            defer { scene.cleanup() }
            await unlock(scene)
            scene.lock.transition(to: .background)
            scene.clock.advance(by: .seconds(delay.seconds) - .milliseconds(1))
            scene.lock.transition(to: .active)
            XCTAssertFalse(scene.lock.isCovered)
            scene.lock.transition(to: .background)
            scene.clock.advance(by: .seconds(delay.seconds))
            scene.lock.transition(to: .active)
            XCTAssertTrue(scene.lock.isCovered)
            await unlock(scene)
            scene.lock.transition(to: .background)
            scene.clock.advance(by: .seconds(delay.seconds + 1))
            scene.lock.transition(to: .active)
            XCTAssertTrue(scene.lock.isCovered)
        }
    }

    func testInactiveAuthenticationPromptDoesNotStartGraceOrCancelRequest() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        scene.lock.unlock()
        await scene.auth.waitForRequests(1)
        scene.lock.transition(to: .inactive)
        scene.clock.advance(by: .seconds(600))
        XCTAssertTrue(scene.lock.isAuthenticating)
        scene.auth.succeed(0)
        await settle()
        XCTAssertTrue(scene.lock.isUnlocked)
        XCTAssertTrue(scene.lock.isCovered, "An inactive scene stays hidden even after authentication")
        scene.lock.transition(to: .active)
        XCTAssertFalse(scene.lock.isCovered)
    }

    func testFailedUnlockAndMissingPasscodeNeverRevealContent() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        scene.lock.unlock()
        await scene.auth.waitForRequests(1)
        scene.auth.fail(0)
        await settle()
        XCTAssertTrue(scene.lock.needsUnlock)
        XCTAssertTrue(scene.lock.isCovered)
        scene.auth.availability = AppAuthenticationAvailability(method: "Device Passcode", unavailableReason: "No passcode")
        scene.lock.unlock()
        XCTAssertTrue(scene.preferences.appLockEnabled)
        XCTAssertTrue(scene.lock.isCovered)
        XCTAssertEqual(scene.lock.errorMessage, "No passcode")
    }

    func testBackgroundOrStopBeforeTaskStartsDoesNotOpenAuthenticationPrompt() async throws {
        for stopping in [false, true] {
            let scene = try Scene()
            defer { scene.cleanup() }
            scene.lock.transition(to: .active)
            scene.lock.setLockEnabled(true)
            if stopping { scene.lock.stop() } else { scene.lock.transition(to: .background) }
            await settle()
            XCTAssertTrue(scene.auth.reasons.isEmpty)
            XCTAssertFalse(scene.preferences.appLockEnabled)
            XCTAssertFalse(scene.lock.isAuthenticating)
        }
    }

    func testSupersededQueuedRequestDoesNotStartAnExtraPrompt() async throws {
        let scene = try Scene()
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        scene.lock.setLockEnabled(true)
        scene.lock.setLockEnabled(true)
        await scene.auth.waitForRequests(1)
        await settle()
        XCTAssertEqual(scene.auth.reasons.count, 1)
        scene.auth.succeed(0)
        await waitUntil { !scene.lock.isAuthenticating }
        XCTAssertTrue(scene.preferences.appLockEnabled)
    }

    func testBackgroundRejectsLateUnlockAndEnableCallbacks() async throws {
        for initiallyLocked in [true, false] {
            let scene = try Scene(locked: initiallyLocked)
            defer { scene.cleanup() }
            scene.auth.ignoresInvalidation = true
            scene.lock.transition(to: .active)
            if initiallyLocked { scene.lock.unlock() } else { scene.lock.setLockEnabled(true) }
            await scene.auth.waitForRequests(1)
            scene.lock.transition(to: .background)
            scene.auth.succeed(0)
            await settle()
            scene.lock.transition(to: .active)
            XCTAssertEqual(scene.preferences.appLockEnabled, initiallyLocked)
            XCTAssertEqual(scene.lock.isCovered, initiallyLocked)
            XCTAssertFalse(scene.lock.isAuthenticating)
        }
    }

    func testBackgroundRejectsLateDisableAndLongerGraceChanges() async throws {
        for disabling in [true, false] {
            let scene = try Scene(locked: true)
            defer { scene.cleanup() }
            await unlock(scene)
            scene.auth.ignoresInvalidation = true
            if disabling { scene.lock.setLockEnabled(false) } else { scene.lock.setLockDelay(.fiveMinutes) }
            await scene.auth.waitForRequests(2)
            scene.lock.transition(to: .background)
            scene.auth.succeed(1)
            await settle()
            scene.lock.transition(to: .active)
            XCTAssertTrue(scene.preferences.appLockEnabled)
            XCTAssertEqual(scene.preferences.lockDelay, .immediately)
            XCTAssertTrue(scene.lock.isCovered)
        }
    }

    func testRepeatedBackgroundEventsDoNotExtendGrace() async throws {
        let scene = try Scene(locked: true, delay: .oneMinute)
        defer { scene.cleanup() }
        await unlock(scene)
        scene.lock.transition(to: .background)
        scene.clock.advance(by: .seconds(30))
        scene.lock.transition(to: .background)
        scene.clock.advance(by: .seconds(30))
        scene.lock.transition(to: .active)
        XCTAssertTrue(scene.lock.isCovered)
    }

    func testNewRequestRejectsPreviousCompletion() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        scene.auth.ignoresInvalidation = true
        scene.lock.transition(to: .active)
        scene.lock.unlock()
        await scene.auth.waitForRequests(1)
        scene.lock.unlock()
        await scene.auth.waitForRequests(2)
        scene.auth.succeed(0)
        await settle()
        XCTAssertTrue(scene.lock.isCovered)
        XCTAssertTrue(scene.lock.isAuthenticating)
        scene.auth.succeed(1)
        await settle()
        XCTAssertFalse(scene.lock.isCovered)
    }

    func testChangedPreferencesRejectCompletionBeforeObservationIsDelivered() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        scene.lock.transition(to: .active)
        scene.lock.unlock()
        await scene.auth.waitForRequests(1)
        scene.preferences.commitLockDelay(.oneMinute)
        scene.auth.succeed(0)
        await settle()
        XCTAssertTrue(scene.lock.needsUnlock)
        XCTAssertFalse(scene.lock.isAuthenticating)
    }

    func testOtherScenesDoNotInheritUnlockedSession() async throws {
        let scene = try Scene(locked: true, delay: .fiveMinutes)
        defer { scene.cleanup() }
        await unlock(scene)
        let other = AppLockController(preferences: scene.preferences, authenticator: TestAuthenticator())
        other.transition(to: .active)
        XCTAssertTrue(other.isCovered)
        XCTAssertFalse(scene.lock.isCovered)
        scene.preferences.commitAppLock(enabled: false)
        other.synchronizePreferences()
        XCTAssertFalse(other.isCovered)
        scene.preferences.commitAppLock(enabled: true)
        scene.lock.synchronizePreferences()
        other.synchronizePreferences()
        XCTAssertTrue(scene.lock.isCovered)
        XCTAssertTrue(other.isCovered)
    }

    func testLockedOrInactiveSceneCannotChangeProtection() throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        scene.lock.setLockEnabled(false)
        scene.lock.setLockDelay(.fiveMinutes)
        scene.lock.unlock()
        scene.lock.transition(to: .active)
        scene.lock.setLockEnabled(false)
        scene.lock.setLockDelay(.fiveMinutes)
        XCTAssertTrue(scene.preferences.appLockEnabled)
        XCTAssertEqual(scene.preferences.lockDelay, .immediately)
        XCTAssertTrue(scene.auth.reasons.isEmpty)
    }

    func testReleasingControllerCancelsItsAuthenticationRequest() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        var owner: AppLockController? = AppLockController(preferences: scene.preferences, authenticator: scene.auth)
        weak var releasedOwner = owner
        owner?.transition(to: .active)
        owner?.unlock()
        await scene.auth.waitForRequests(1)
        owner = nil
        XCTAssertNil(releasedOwner)
        await waitUntil { scene.auth.cancelledRequests == 1 }
        XCTAssertTrue(scene.preferences.appLockEnabled)
    }

    func testStopInvalidatesSessionAndLateCallback() async throws {
        let scene = try Scene(locked: true)
        defer { scene.cleanup() }
        scene.auth.ignoresInvalidation = true
        scene.lock.transition(to: .active)
        scene.lock.unlock()
        await scene.auth.waitForRequests(1)
        scene.lock.stop()
        scene.auth.succeed(0)
        await settle()
        XCTAssertTrue(scene.lock.isCovered)
        XCTAssertFalse(scene.lock.isUnlocked)
    }

    private func unlock(_ scene: Scene) async {
        scene.lock.transition(to: .active)
        let request = scene.auth.reasons.count
        scene.lock.unlock()
        await scene.auth.waitForRequests(request + 1)
        scene.auth.succeed(request)
        await settle()
        XCTAssertFalse(scene.lock.needsUnlock)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Authentication did not reach its expected state")
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class Scene {
    let suite = "AppLockControllerTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let preferences: IOSPreferences
    let auth = TestAuthenticator()
    let clock = TestClock()
    let lock: AppLockController

    init(locked: Bool = false, delay: IOSLockDelay = .immediately) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences = IOSPreferences(defaults: defaults)
        preferences.commitAppLock(enabled: locked)
        preferences.commitLockDelay(delay)
        let clock = clock
        lock = AppLockController(preferences: preferences, authenticator: auth, now: { clock.instant })
    }

    func cleanup() {
        auth.ignoresInvalidation = false
        lock.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class TestClock {
    var instant = ContinuousClock.now
    func advance(by duration: Duration) { instant = instant.advanced(by: duration) }
}

@MainActor
private final class TestAuthenticator: AppAuthenticating {
    var availability = AppAuthenticationAvailability(method: "Face ID", unavailableReason: nil)
    var ignoresInvalidation = false
    private(set) var reasons: [String] = []
    private(set) var cancelledRequests = 0
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]

    func authenticate(reason: String) async throws {
        let index = reasons.count
        reasons.append(reason)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[index] = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(index) }
        }
    }

    func invalidate() {
        guard !ignoresInvalidation else { return }
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(_ index: Int) {
        guard !ignoresInvalidation, let continuation = pending.removeValue(forKey: index) else { return }
        cancelledRequests += 1
        continuation.resume(throwing: CancellationError())
    }

    func succeed(_ index: Int) { pending.removeValue(forKey: index)?.resume() }
    func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: CancellationError()) }

    func waitForRequests(_ count: Int) async {
        for _ in 0..<100 where reasons.count < count { await Task.yield() }
        XCTAssertEqual(reasons.count, count)
    }
}
