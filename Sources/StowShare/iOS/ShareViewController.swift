import StowCore
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareCaptureModel()
    private var host: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let saveImmediately = StowShareSettings().savesSharedItemsImmediately
        installHost(rootView: saveImmediately ? AnyView(DirectShareSaveProgressView()) : confirmationView())

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { [weak self] in
            await self?.load(items: items, saveImmediately: saveImmediately)
        }
    }

    private func installHost(rootView: AnyView) {
        let host = UIHostingController(rootView: rootView)
        self.host = host
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
    }

    private func load(items: [NSExtensionItem], saveImmediately: Bool) async {
        await model.load(from: items)
        guard saveImmediately else { return }

        guard model.errorMessage == nil else {
            host?.rootView = confirmationView()
            return
        }
        do {
            try model.save()
            finish(saved: true)
        } catch {
            model.errorMessage = error.localizedDescription
            host?.rootView = confirmationView()
        }
    }

    private func confirmationView() -> AnyView {
        AnyView(ShareCaptureView(model: model) { [weak self] saved in
            self?.finish(saved: saved)
        })
    }

    private func finish(saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}

private struct DirectShareSaveProgressView: View {
    var body: some View {
        ProgressView("Saving to Stow…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("share-direct-save-progress")
    }
}
