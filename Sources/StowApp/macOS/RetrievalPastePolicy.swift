import AppKit

@MainActor
protocol RetrievalDirectPasteCapability {
    var canPasteDirectly: Bool { get }
}

@MainActor
protocol RetrievalPasteTargetState {
    var isTerminated: Bool { get }
}

extension NSRunningApplication: RetrievalPasteTargetState {}

enum RetrievalCopyFallbackReason: Equatable {
    case targetMissing
    case targetTerminated
    case accessibilityUnavailable
}

enum RetrievalPasteOutcome: Equatable {
    case directPaste
    case copyFallback(RetrievalCopyFallbackReason)
}

@MainActor
enum RetrievalPastePolicy {
    static func outcome(
        capability: any RetrievalDirectPasteCapability,
        target: (any RetrievalPasteTargetState)?
    ) -> RetrievalPasteOutcome {
        guard let target else { return .copyFallback(.targetMissing) }
        guard !target.isTerminated else { return .copyFallback(.targetTerminated) }
        guard capability.canPasteDirectly else { return .copyFallback(.accessibilityUnavailable) }
        return .directPaste
    }
}

enum RetrievalPastePresentation {
    static let copyFallbackMessage = "Copied — paste with Command-V"

    static func statusLabel(directAvailable: Bool, compact: Bool) -> String {
        if directAvailable { return compact ? "Direct" : "Paste: Direct" }
        return compact ? "Copy only" : "Paste: Copy only"
    }

    static func statusAccessibilityLabel(directAvailable: Bool) -> String {
        directAvailable ? "Paste mode: Direct" : "Paste mode: Copy only"
    }
}
