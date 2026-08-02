import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ShareCaptureView: View {
    @State var model: ShareCaptureModel
    let onComplete: (Bool) -> Void
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    if model.isLoading { ProgressView("Loading…") }
                    else {
                        if let data = model.previewImageData, let image = previewImage(data) {
                            image.resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Text(model.preview).lineLimit(5).textSelection(.enabled)
                    }
                }
                Section("Details") {
                    TextField("Title", text: $model.title)
                    TextField("Note (optional)", text: $model.note, axis: .vertical)
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    Toggle("Pin", isOn: $model.isPinned)
                    if model.canSaveAsCode {
                        Toggle("Save as Code", isOn: $model.saveAsCode)
                        if model.saveAsCode { TextField("Language (optional)", text: $model.language) }
                    }
                    Toggle("Directly Archive", isOn: $model.directlyArchive)
                }
                if let error = model.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Save to Stow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onComplete(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try model.save(); onComplete(true) }
                        catch { model.errorMessage = error.localizedDescription }
                    }
                    .disabled(model.isLoading || model.isSaving || model.errorMessage != nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func previewImage(_ data: Data) -> Image? {
        #if os(iOS)
        return UIImage(data: data).map(Image.init(uiImage:))
        #elseif os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}
