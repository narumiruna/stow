import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareCaptureModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(model: model) { [weak self] saved in
            if saved { self?.extensionContext?.completeRequest(returningItems: nil) }
            else { self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        Task { await model.load(from: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []) }
    }
}
