import XCTest
@testable import StowApp

@MainActor
final class RetrievalPastePolicyTests: XCTestCase {
    func testDirectPasteRequiresCapabilityAndRunningTarget() {
        let capability = PasteCapabilityDouble(canPasteDirectly: true)
        let target = PasteTargetDouble(isTerminated: false)

        XCTAssertEqual(
            RetrievalPastePolicy.outcome(capability: capability, target: target),
            .directPaste
        )
    }

    func testMissingTargetUsesCopyFallback() {
        XCTAssertEqual(
            RetrievalPastePolicy.outcome(
                capability: PasteCapabilityDouble(canPasteDirectly: true),
                target: nil
            ),
            .copyFallback(.targetMissing)
        )
    }

    func testTerminatedTargetUsesCopyFallback() {
        XCTAssertEqual(
            RetrievalPastePolicy.outcome(
                capability: PasteCapabilityDouble(canPasteDirectly: true),
                target: PasteTargetDouble(isTerminated: true)
            ),
            .copyFallback(.targetTerminated)
        )
    }

    func testUnavailableAccessibilityUsesCopyFallbackWithoutPrompting() {
        XCTAssertEqual(
            RetrievalPastePolicy.outcome(
                capability: PasteCapabilityDouble(canPasteDirectly: false),
                target: PasteTargetDouble(isTerminated: false)
            ),
            .copyFallback(.accessibilityUnavailable)
        )
    }

    func testStatusLabelsRemainConciseAndAccessible() {
        XCTAssertEqual(
            RetrievalPastePresentation.statusLabel(directAvailable: true, compact: false),
            "Paste: Direct"
        )
        XCTAssertEqual(
            RetrievalPastePresentation.statusLabel(directAvailable: false, compact: true),
            "Copy only"
        )
        XCTAssertEqual(
            RetrievalPastePresentation.statusAccessibilityLabel(directAvailable: true),
            "Paste mode: Direct"
        )
        XCTAssertEqual(
            RetrievalPastePresentation.statusAccessibilityLabel(directAvailable: false),
            "Paste mode: Copy only"
        )
    }
}

final class DirectPasteLaunchPromptPolicyTests: XCTestCase {
    func testPromptsOnceOnFirstLaunchWithoutAccess() {
        XCTAssertTrue(DirectPasteLaunchPromptPolicy.shouldPrompt(alreadyPrompted: false, accessGranted: false, isAutomatedLaunch: false))
    }

    func testDoesNotPromptAgainAfterTheFirstLaunch() {
        XCTAssertFalse(DirectPasteLaunchPromptPolicy.shouldPrompt(alreadyPrompted: true, accessGranted: false, isAutomatedLaunch: false))
    }

    func testDoesNotPromptWhenAccessIsAlreadyGranted() {
        XCTAssertFalse(DirectPasteLaunchPromptPolicy.shouldPrompt(alreadyPrompted: false, accessGranted: true, isAutomatedLaunch: false))
    }

    func testDoesNotPromptDuringAutomatedLaunches() {
        XCTAssertFalse(DirectPasteLaunchPromptPolicy.shouldPrompt(alreadyPrompted: false, accessGranted: false, isAutomatedLaunch: true))
    }
}

@MainActor
private struct PasteCapabilityDouble: RetrievalDirectPasteCapability {
    let canPasteDirectly: Bool
}

@MainActor
private struct PasteTargetDouble: RetrievalPasteTargetState {
    let isTerminated: Bool
}

final class DirectPasteAvailabilityTests: XCTestCase {
    func testSandboxBlocksDirectPasteEvenWithPermissions() {
        XCTAssertEqual(DirectPasteAvailability.evaluate(isSandboxed: true, accessibilityTrusted: true, canPostEvents: true), .sandboxed)
    }

    func testRequiresAccessibilityAndEventPosting() {
        XCTAssertEqual(DirectPasteAvailability.evaluate(isSandboxed: false, accessibilityTrusted: false, canPostEvents: true), .accessibilityNotTrusted)
        XCTAssertEqual(DirectPasteAvailability.evaluate(isSandboxed: false, accessibilityTrusted: true, canPostEvents: false), .eventPostingNotAllowed)
        XCTAssertEqual(DirectPasteAvailability.evaluate(isSandboxed: false, accessibilityTrusted: true, canPostEvents: true), .available)
    }
}

@MainActor
final class DirectPastePerformerTests: XCTestCase {
    func testPastesToTargetPidOnceItBecomesFrontmost() async {
        let target = TargetDouble(pid: 42)
        let environment = EnvironmentDouble(frontmostSequence: [7, 7, 7, 42])
        let result = await DirectPastePerformer(environment: environment).paste(into: target)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(environment.postedPIDs, [42])
        XCTAssertTrue(environment.waits.allSatisfy { $0 == DirectPastePerformer.pollIntervalMilliseconds })
    }

    func testAlreadyFrontmostTargetPastesWithoutWaiting() async {
        let environment = EnvironmentDouble(frontmostSequence: [42])
        let result = await DirectPastePerformer(environment: environment).paste(into: TargetDouble(pid: 42))
        XCTAssertEqual(result, .pasted)
        XCTAssertTrue(environment.waits.isEmpty)
    }

    func testUnavailableDoesNotActivateOrPost() async {
        let target = TargetDouble(pid: 42)
        let environment = EnvironmentDouble(frontmostSequence: [7], availability: [.accessibilityNotTrusted])
        let result = await DirectPastePerformer(environment: environment).paste(into: target)
        XCTAssertEqual(result, .failed(.unavailable(.accessibilityNotTrusted)))
        XCTAssertEqual(target.activationCount, 0)
        XCTAssertTrue(environment.postedPIDs.isEmpty)
    }

    func testFailedActivationFallsBack() async {
        let target = TargetDouble(pid: 42, activationSucceeds: false)
        let environment = EnvironmentDouble(frontmostSequence: [7])
        let result = await DirectPastePerformer(environment: environment).paste(into: target)
        XCTAssertEqual(result, .failed(.activationFailed))
        XCTAssertTrue(environment.postedPIDs.isEmpty)
    }

    func testFocusTimeoutAfterMaximumChecks() async {
        let environment = EnvironmentDouble(frontmostSequence: [7])
        let result = await DirectPastePerformer(environment: environment).paste(into: TargetDouble(pid: 42))
        XCTAssertEqual(result, .failed(.focusTimeout))
        XCTAssertEqual(environment.waits.count, DirectPastePerformer.maximumFocusChecks)
        XCTAssertTrue(environment.postedPIDs.isEmpty)
    }

    func testPermissionRevokedWhileWaitingAborts() async {
        let environment = EnvironmentDouble(
            frontmostSequence: [7],
            availability: [.available, .eventPostingNotAllowed]
        )
        let result = await DirectPastePerformer(environment: environment).paste(into: TargetDouble(pid: 42))
        XCTAssertEqual(result, .failed(.unavailable(.eventPostingNotAllowed)))
        XCTAssertTrue(environment.postedPIDs.isEmpty)
    }

    func testTargetQuittingWhileWaitingAborts() async {
        let target = TargetDouble(pid: 42)
        let environment = EnvironmentDouble(frontmostSequence: [7])
        environment.onWait = { target.isTerminated = true }
        let result = await DirectPastePerformer(environment: environment).paste(into: target)
        XCTAssertEqual(result, .failed(.targetTerminated))
    }

    func testFocusStolenBeforePostingAborts() async {
        let environment = EnvironmentDouble(frontmostSequence: [7, 42, 99])
        let result = await DirectPastePerformer(environment: environment).paste(into: TargetDouble(pid: 42))
        XCTAssertEqual(result, .failed(.focusLost))
        XCTAssertTrue(environment.postedPIDs.isEmpty)
    }

    func testEventPostingFailureIsReported() async {
        let environment = EnvironmentDouble(frontmostSequence: [42], postSucceeds: false)
        let result = await DirectPastePerformer(environment: environment).paste(into: TargetDouble(pid: 42))
        XCTAssertEqual(result, .failed(.eventPostingFailed))
    }
}

@MainActor
final class RetrievalReturnKeyTests: XCTestCase {
    func testReturnAndKeypadEnterTriggerDefaultPaste() {
        XCTAssertEqual(RetrievalReturnKey.plainTextRequest(keyCode: 36, modifiers: []), false)
        XCTAssertEqual(RetrievalReturnKey.plainTextRequest(keyCode: 76, modifiers: [.numericPad, .function]), false)
    }

    func testShiftRequestsPlainText() {
        XCTAssertEqual(RetrievalReturnKey.plainTextRequest(keyCode: 36, modifiers: .shift), true)
        XCTAssertEqual(RetrievalReturnKey.plainTextRequest(keyCode: 76, modifiers: [.shift, .numericPad]), true)
    }

    func testOtherKeysAndModifiersAreIgnored() {
        XCTAssertNil(RetrievalReturnKey.plainTextRequest(keyCode: 9, modifiers: []))
        XCTAssertNil(RetrievalReturnKey.plainTextRequest(keyCode: 36, modifiers: .command))
        XCTAssertNil(RetrievalReturnKey.plainTextRequest(keyCode: 36, modifiers: [.shift, .option]))
    }
}

@MainActor
final class PanelCardHitTestingTests: XCTestCase {
    func testConvertsSuperviewPointsBeforeComparing() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let card = NSView(frame: NSRect(x: 300, y: 20, width: 200, height: 150))
        container.addSubview(card)

        XCTAssertTrue(PanelCardHitTesting.contains(superviewPoint: NSPoint(x: 400, y: 100), in: card))
        XCTAssertFalse(PanelCardHitTesting.contains(superviewPoint: NSPoint(x: 100, y: 100), in: card))
    }
}

@MainActor
private final class TargetDouble: DirectPasteTarget {
    let processIdentifier: pid_t
    var isTerminated = false
    let activationSucceeds: Bool
    private(set) var activationCount = 0

    init(pid: pid_t, activationSucceeds: Bool = true) {
        processIdentifier = pid
        self.activationSucceeds = activationSucceeds
    }

    func activateForPaste() -> Bool {
        activationCount += 1
        return activationSucceeds
    }
}

/// Returns scripted values; the last value in each sequence repeats.
@MainActor
private final class EnvironmentDouble: DirectPasteEnvironment {
    private var frontmostSequence: [pid_t]
    private var availabilitySequence: [DirectPasteAvailability]
    private let postSucceeds: Bool
    private(set) var postedPIDs: [pid_t] = []
    private(set) var waits: [Int] = []
    var onWait: (() -> Void)?

    init(frontmostSequence: [pid_t], availability: [DirectPasteAvailability] = [.available], postSucceeds: Bool = true) {
        self.frontmostSequence = frontmostSequence
        availabilitySequence = availability
        self.postSucceeds = postSucceeds
    }

    func availability() -> DirectPasteAvailability {
        availabilitySequence.count > 1 ? availabilitySequence.removeFirst() : availabilitySequence[0]
    }

    func frontmostProcessIdentifier() -> pid_t? {
        frontmostSequence.count > 1 ? frontmostSequence.removeFirst() : frontmostSequence[0]
    }

    func postCommandV(to pid: pid_t) -> Bool {
        postedPIDs.append(pid)
        return postSucceeds
    }

    func wait(milliseconds: Int) async {
        waits.append(milliseconds)
        onWait?()
    }
}
