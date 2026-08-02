import CoreData
import Foundation

@MainActor
final class CloudSyncMonitor {
    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case paused(String)

        var title: String {
            switch self {
            case .idle: "Waiting for iCloud"
            case .syncing: "Syncing…"
            case .synced: "Up to date"
            case .paused: "Sync paused"
            }
        }

        var guidance: String? {
            switch self {
            case .paused(let message): "Check your connection and iCloud settings, then reopen Stow. \(message)"
            default: nil
            }
        }
    }

    var onChange: ((Status) -> Void)?
    private(set) var status: Status = .idle { didSet { onChange?(status) } }
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let endDate = event.endDate
            let succeeded = event.succeeded
            let message = event.error?.localizedDescription
            MainActor.assumeIsolated { self?.apply(endDate: endDate, succeeded: succeeded, errorMessage: message) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func apply(endDate: Date?, succeeded: Bool, errorMessage: String?) {
        if endDate == nil {
            status = .syncing
        } else if succeeded {
            status = .synced(endDate ?? Date())
        } else {
            status = .paused(errorMessage ?? "iCloud is temporarily unavailable.")
        }
    }
}
