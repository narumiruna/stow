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
}
