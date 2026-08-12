import AppKit
import StowCore

struct ClipboardPasteboardTypeIdentifier {
    static let concealed = "org.nspasteboard.ConcealedType"
    static let transient = "org.nspasteboard.TransientType"
    static let stowOwned = StowRepresentationType.stowOwned
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

struct ClipboardPasteboardSnapshot {
    let candidates: [PasteboardRepresentationCandidate]
    let urls: [URL]
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
    func readSnapshot() -> ClipboardPasteboardSnapshot
}

extension ClipboardPasteboardReading {
    func readSnapshot() -> ClipboardPasteboardSnapshot {
        var candidates: [PasteboardRepresentationCandidate] = []
        if let string = readString() {
            candidates.append(PasteboardRepresentationCandidate(
                typeIdentifier: StowRepresentationType.plainText,
                data: Data(string.utf8)
            ))
        }
        return ClipboardPasteboardSnapshot(candidates: candidates, urls: readURLs())
    }
}

@MainActor
final class SystemClipboardPasteboardReader: ClipboardPasteboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var advertisedTypeIdentifiers: [String] {
        pasteboard.pasteboardItems?.flatMap { $0.types.map(\.rawValue) } ?? pasteboard.types?.map(\.rawValue) ?? []
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

    func readSnapshot() -> ClipboardPasteboardSnapshot {
        guard let item = pasteboard.pasteboardItems?.first else {
            return ClipboardPasteboardSnapshot(candidates: [], urls: readURLs())
        }
        let safeTypes: [(NSPasteboard.PasteboardType, String)] = [
            (.string, StowRepresentationType.plainText),
            (.rtf, StowRepresentationType.rtf),
            (.html, StowRepresentationType.html),
            (.URL, StowRepresentationType.url),
            (.png, StowRepresentationType.png),
            (.tiff, StowRepresentationType.tiff),
        ]
        let candidates = safeTypes.compactMap { pasteboardType, identifier -> PasteboardRepresentationCandidate? in
            guard item.types.contains(pasteboardType) else { return nil }
            let data: Data?
            if pasteboardType == .string || pasteboardType == .URL {
                data = item.string(forType: pasteboardType).map { Data($0.utf8) }
            } else {
                data = item.data(forType: pasteboardType)
            }
            return data.map { PasteboardRepresentationCandidate(typeIdentifier: identifier, data: $0) }
        }
        return ClipboardPasteboardSnapshot(candidates: candidates, urls: readURLs())
    }
}
