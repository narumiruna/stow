import Darwin
import Dispatch
import Foundation
import StowCore

@MainActor
final class StowAutomationController {
    private let spool: StowAutomationSpool
    private let service: StowAutomationHostService
    private let maintenanceInterval: Duration
    private var directorySource: DispatchSourceFileSystemObject?
    private var pendingDirectoryDescriptor: Int32 = -1
    private var drainTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?

    init(
        model: AppModel,
        rootURL: URL,
        maintenanceInterval: Duration = .seconds(3_600)
    ) throws {
        let spool = try StowAutomationSpool(rootURL: rootURL)
        self.spool = spool
        service = StowAutomationHostService(model: model, spool: spool)
        self.maintenanceInterval = maintenanceInterval
    }

    var hasPendingRequests: Bool {
        spool.hasPendingRequests()
    }

    func start() {
        guard directorySource == nil else { return }
        do {
            try spool.recoverInterruptedProcessing()
        } catch {
            reportTransportFailure()
        }
        performMaintenance()

        pendingDirectoryDescriptor = open(spool.pendingDirectoryURL.path, O_EVTONLY)
        guard pendingDirectoryDescriptor >= 0 else {
            reportTransportFailure()
            return
        }
        let descriptor = pendingDirectoryDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleDrain() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        directorySource = source
        scheduleDrain()
        source.resume()
        scheduleDrain()
        scheduleMaintenance()
    }

    func stop() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        drainTask?.cancel()
        drainTask = nil
        directorySource?.cancel()
        directorySource = nil
        pendingDirectoryDescriptor = -1
    }

    private func scheduleDrain() {
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await drain()
            drainTask = nil
            if spool.hasPendingRequests() { scheduleDrain() }
        }
    }

    private func drain() async {
        do {
            while !Task.isCancelled, let claim = try spool.claimNext() {
                let response = await service.execute(claim.request)
                try spool.complete(claim, with: response)
            }
        } catch {
            reportTransportFailure()
        }
    }

    private func scheduleMaintenance() {
        guard maintenanceTask == nil else { return }
        let interval = maintenanceInterval
        maintenanceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.performMaintenance()
            }
        }
    }

    private func performMaintenance() {
        do {
            _ = try spool.removeInterruptedStaging()
            _ = try spool.removeCompletedArtifacts()
        } catch {
            reportTransportFailure()
        }
    }

    private func reportTransportFailure() {
        fputs("Stow automation transport failed.\n", stderr)
    }
}
