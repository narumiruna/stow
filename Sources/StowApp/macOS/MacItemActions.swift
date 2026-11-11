import StowCore

extension AppModel {
    @discardableResult
    func copy(
        _ item: StowItem,
        attachment: StowAttachment?,
        format: PasteFormat = .original,
        writer: any PlatformPasteboardWriting = SystemPlatformPasteboardWriter()
    ) -> Bool {
        let representations = representations(for: item)
        return performUse(item, action: .copy, metric: .itemCopied) {
            try PlatformActions.copy(
                item, attachment: attachment, representations: representations,
                format: format, writer: writer
            )
        }
    }

    /// Writes the pasteboard now and returns the use accounting to run after the panel closes or cancels its close,
    /// or nil when the write failed.
    func copyDeferringAccounting(
        _ item: StowItem,
        attachment: StowAttachment?,
        format: PasteFormat = .original,
        writer: any PlatformPasteboardWriting = SystemPlatformPasteboardWriter()
    ) -> (() -> Void)? {
        let representations = representations(for: item)
        return performUseDeferringAccounting(item, action: .copy, metric: .itemCopied) {
            try PlatformActions.copy(
                item, attachment: attachment, representations: representations,
                format: format, writer: writer
            )
        }
    }

    /// Writes several text-like items to the pasteboard as one plain-text payload, in the given order,
    /// and returns the use accounting for every item, or nil when the items cannot be combined or the write failed.
    func copyCombinedDeferringAccounting(
        _ items: [StowItem],
        writer: any PlatformPasteboardWriting = SystemPlatformPasteboardWriter()
    ) -> (() -> Void)? {
        performUseDeferringAccounting(items, action: .copy, metric: .itemCopied) {
            let payload = try PastePayloadBuilder.buildCombined(items: items)
            guard writer.write(payload) else { throw PlatformActionError.unavailable }
        }
    }
}
