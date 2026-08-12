import AppKit

struct ClipboardPasteboardTypeIdentifier {
    static let concealed = "org.nspasteboard.ConcealedType"
    static let transient = "org.nspasteboard.TransientType"
    static let stowOwned = "dev.narumi.stow.owned-content"
}

enum ClipboardCaptureIgnoreReason: Equatable {
    case concealed
    case transient
    case stowOwned
}

enum ClipboardCaptureDecision: Equatable {
    case capture
    case ignore(ClipboardCaptureIgnoreReason)
}

enum ClipboardCapturePolicy {
    static func decision(for advertisedTypeIdentifiers: [String]) -> ClipboardCaptureDecision {
        let identifiers = Set(advertisedTypeIdentifiers)
        if identifiers.contains(ClipboardPasteboardTypeIdentifier.concealed) {
            return .ignore(.concealed)
        }
        if identifiers.contains(ClipboardPasteboardTypeIdentifier.transient) {
            return .ignore(.transient)
        }
        if identifiers.contains(ClipboardPasteboardTypeIdentifier.stowOwned) {
            return .ignore(.stowOwned)
        }
        return .capture
    }
}

extension NSPasteboard.PasteboardType {
    static let stowOwnedContent = NSPasteboard.PasteboardType(
        ClipboardPasteboardTypeIdentifier.stowOwned
    )
}

@MainActor
protocol ClipboardPasteboardReading: AnyObject {
    var changeCount: Int { get }
    var advertisedTypeIdentifiers: [String] { get }
    var captureAccessAllowed: Bool { get }
    var statusText: String { get }

    func readURLs() -> [URL]
    func readImage() -> NSImage?
    func readString() -> String?
}

@MainActor
final class SystemClipboardPasteboardReader: ClipboardPasteboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var advertisedTypeIdentifiers: [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    var captureAccessAllowed: Bool {
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .default, .alwaysAllow:
                return true
            case .ask, .alwaysDeny:
                return false
            @unknown default:
                return false
            }
        }
        return true
    }

    var statusText: String {
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .default: return "Permission not requested"
            case .ask: return "Needs Always Allow"
            case .alwaysAllow: return "Always Allow"
            case .alwaysDeny: return "Blocked by macOS"
            @unknown default: return "Unknown"
            }
        }
        return "Monitoring"
    }

    func readURLs() -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self]) ?? []).compactMap { object in
            (object as? NSURL).map { $0 as URL }
        }
    }

    func readImage() -> NSImage? {
        NSImage(pasteboard: pasteboard)
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }
}
