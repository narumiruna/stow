import Observation
import SwiftUI
import StowCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct StowShareButton: View {
    @Environment(AppModel.self) private var appModel
    let item: StowItem
    let attachment: StowAttachment?
    let fillsWidth: Bool
    #if os(iOS)
    @State private var activityItems: [Any] = []
    @State private var presenting = false
    #elseif os(macOS)
    @State private var coordinator = MacShareCoordinator()
    #endif

    init(item: StowItem, attachment: StowAttachment?, fillsWidth: Bool = false) {
        self.item = item
        self.attachment = attachment
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        Button { share() } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        #if os(iOS)
        .sheet(isPresented: $presenting) {
            ActivitySheet(items: activityItems) { completed, error in
                presenting = false
                if completed { recordSuccess() }
                else if let error { appModel.presentedError = error.localizedDescription }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
    }

    private func share() {
        do {
            let items = try shareItems()
            #if os(iOS)
            activityItems = items
            presenting = true
            #elseif os(macOS)
            coordinator.present(items: items, onSuccess: recordSuccess, onFailure: { appModel.presentedError = $0.localizedDescription })
            #endif
        } catch { appModel.presentedError = error.localizedDescription }
    }

    private func shareItems() throws -> [Any] {
        if let attachment { return [try PlatformActions.materialize(attachment)] }
        if item.type == .link, let rawURL = item.urlString, let url = URL(string: rawURL) { return [url] }
        return [item.textContent ?? item.title]
    }

    private func recordSuccess() {
        appModel.performUse(item, action: .share, metric: .itemShared) {}
    }
}

#if os(iOS)
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in completion(completed, error) }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
@MainActor
@Observable
private final class MacShareCoordinator: NSObject, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var picker: NSSharingServicePicker?
    private var onSuccess: (() -> Void)?
    private var onFailure: ((Error) -> Void)?

    func present(items: [Any], onSuccess: @escaping () -> Void, onFailure: @escaping (Error) -> Void) {
        guard let view = NSApp.keyWindow?.contentView else { onFailure(PlatformActionError.unavailable); return }
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        service?.delegate = self
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        onSuccess?()
        clear()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        onFailure?(error)
        clear()
    }

    private func clear() {
        picker = nil
        onSuccess = nil
        onFailure = nil
    }
}
#endif
