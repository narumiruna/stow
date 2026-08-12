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

    func testStatusLabelsAndFallbackGuidanceRemainConciseAndAccessible() {
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
        XCTAssertEqual(
            RetrievalPastePresentation.copyFallbackMessage,
            "Copied — paste with Command-V"
        )
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
