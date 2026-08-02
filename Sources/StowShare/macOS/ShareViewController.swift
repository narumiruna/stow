import AppKit
import SwiftUI

final class ShareViewController: NSViewController {
    private let model = ShareCaptureModel()

    override func loadView() {
        let host = NSHostingController(rootView: ShareCaptureView(model: model) { [weak self] saved in
            if saved { self?.extensionContext?.completeRequest(returningItems: nil) }
            else { self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
        })
        view = host.view
        addChild(host)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await model.load(from: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []) }
    }
}
