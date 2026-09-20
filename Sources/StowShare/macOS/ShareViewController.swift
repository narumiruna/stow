import AppKit
import SwiftUI

final class ShareViewController: NSViewController {
    private let model = ShareCaptureModel()
    private var loadingTask: Task<Void, Never>?
    private var didFinish = false

    override func loadView() {
        let host = NSHostingController(rootView: ShareCaptureView(model: model) { [weak self] saved in
            self?.finish(saved: saved)
        })
        view = host.view
        addChild(host)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            await self?.model.load(from: items)
        }
    }

    deinit {
        loadingTask?.cancel()
        Task { @MainActor [model] in model.cancel() }
    }

    private func finish(saved: Bool) {
        guard !didFinish else { return }
        didFinish = true
        loadingTask?.cancel()
        loadingTask = nil
        model.cancel()
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
