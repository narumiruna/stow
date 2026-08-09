import AppKit
import StowCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MacAppCoordinator: NSObject, NSApplicationDelegate {
    private(set) static var dependencies: (model: AppModel, container: ModelContainer)?

    static func install(model: AppModel, container: ModelContainer) {
        dependencies = (model, container)
    }
    private let hotKeys = GlobalHotKeyService()
    private let retrievalPanel = RetrievalPanelController()
    private let quickCapturePanel = QuickCapturePanelController()
    private let clipboardMonitor = ClipboardMonitor()
    private weak var model: AppModel?
    private var container: ModelContainer?
    private var pendingAction: GlobalHotKeyService.Action?
    private var pendingRegistrationError: String?
    private var pendingClipboardContents: [ClipboardMonitor.CapturedContent] = []
    private var clipboardStartupTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        retrievalPanel.destinationHandler = { [weak self] destination in
            self?.present(destination)
        }
        if let dependencies = Self.dependencies {
            model = dependencies.model
            container = dependencies.container
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reloadHotKeys), name: .stowHotKeysChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadClipboardMonitoring), name: .stowClipboardMonitoringChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showQuickPanel), name: .stowShowQuickPanel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showQuickAdd), name: .stowShowQuickAdd, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openLibrary), name: .stowOpenLibrary, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .stowOpenSettings, object: nil)
        hotKeys.handler = { [weak self] action in self?.handle(action) }
        clipboardMonitor.captureHandler = { [weak self] content in self?.handle(content) }
        clipboardMonitor.statusHandler = { [weak self] status in
            self?.model?.clipboardMonitoringStatus = status
        }
        clipboardMonitor.errorHandler = { [weak self] error in
            self?.model?.presentedError = "Clipboard capture failed: \(error.localizedDescription)"
        }
        registerHotKeys()
        configureClipboardMonitoring()
        #if DEBUG
        let hidesLibraryOnLaunch = ProcessInfo.processInfo.arguments.contains("--ui-testing-utility-mode")
        #else
        let hidesLibraryOnLaunch = !ProcessInfo.processInfo.arguments.contains("--open-library")
        #endif
        if hidesLibraryOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain { window.orderOut(nil) }
            }
        } else if ProcessInfo.processInfo.arguments.contains("--open-library") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.retrievalPanel.openLibrary() }
        }
    }

    @objc private func reloadHotKeys() { registerHotKeys() }
    @objc private func reloadClipboardMonitoring() { configureClipboardMonitoring() }
    @objc private func showQuickPanel() { handle(.quickPanel) }
    @objc private func showQuickAdd() { handle(.quickAdd) }
    @objc private func openLibrary() { retrievalPanel.openLibrary() }
    @objc private func openSettings() { retrievalPanel.openSettings() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { retrievalPanel.openLibrary() }
        return true
    }

    private func registerHotKeys() {
        do {
            try hotKeys.registerDefaults()
            pendingRegistrationError = nil
            model?.globalShortcutStatus = "Registered"
        } catch {
            pendingRegistrationError = error.localizedDescription
            model?.globalShortcutStatus = error.localizedDescription
            model?.presentedError = error.localizedDescription
        }
    }

    func configure(model: AppModel, container: ModelContainer) {
        self.model = model
        self.container = container
        registerHotKeys()
        configureClipboardMonitoring()
        if let pendingRegistrationError { model.presentedError = pendingRegistrationError }
        if let pendingAction {
            self.pendingAction = nil
            handle(pendingAction)
        }
    }

    private func configureClipboardMonitoring() {
        clipboardStartupTask?.cancel()
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "clipboardMonitoringEnabled") == nil || defaults.bool(forKey: "clipboardMonitoringEnabled")
        guard enabled else {
            clipboardMonitor.stop()
            model?.clipboardMonitoringStatus = "Off"
            discardPendingClipboardContents()
            return
        }

        clipboardMonitor.start()
        model?.clipboardMonitoringStatus = clipboardMonitor.statusText
        guard model != nil else { return }
        clipboardStartupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let model = self.model else { return }
                if model.isReadyForCapture {
                    let pendingContents = self.pendingClipboardContents
                    self.pendingClipboardContents.removeAll()
                    for content in pendingContents { self.persist(content, using: model) }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func handle(_ content: ClipboardMonitor.CapturedContent) {
        guard let model, model.isReadyForCapture else {
            pendingClipboardContents.append(content)
            return
        }
        persist(content, using: model)
    }

    private func persist(_ content: ClipboardMonitor.CapturedContent, using model: AppModel) {
        switch content {
        case .draft(let draft):
            model.create(draft)
        case .attachment(let draft, let fileURL):
            model.createAttachment(draft, fileURL: fileURL)
        }
    }

    private func discardPendingClipboardContents() {
        for case .attachment(_, let fileURL) in pendingClipboardContents {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        pendingClipboardContents.removeAll()
    }

    private func handle(_ action: GlobalHotKeyService.Action) {
        guard model != nil, container != nil else {
            pendingAction = action
            return
        }
        switch action {
        case .quickAdd:
            if retrievalPanel.isVisible {
                retrievalPanel.requestClose(.destination(.quickAdd))
            } else {
                presentQuickAdd()
            }
        case .quickPanel:
            if let model, let container { retrievalPanel.present(model: model, container: container) }
        }
    }

    private func present(_ destination: QuickPanelDestination) {
        switch destination {
        case .quickAdd:
            presentQuickAdd()
        case .library:
            retrievalPanel.presentLibrary()
        case .settings:
            retrievalPanel.presentSettings()
        }
    }

    private func presentQuickAdd() {
        guard let model, let container else { return }
        model.isAdding = false
        quickCapturePanel.present(model: model, container: container)
    }
}

extension Notification.Name {
    static let stowHotKeysChanged = Notification.Name("StowHotKeysChanged")
    static let stowClipboardMonitoringChanged = Notification.Name("StowClipboardMonitoringChanged")
    static let stowShowQuickPanel = Notification.Name("StowShowQuickPanel")
    static let stowShowQuickAdd = Notification.Name("StowShowQuickAdd")
    static let stowOpenLibrary = Notification.Name("StowOpenLibrary")
    static let stowOpenSettings = Notification.Name("StowOpenSettings")
}

extension NSPasteboard.PasteboardType {
    static let stowOwnedContent = NSPasteboard.PasteboardType("dev.narumi.stow.owned-content")
}

@MainActor
private final class QuickCapturePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func present(model: AppModel, container: ModelContainer) {
        if let panel, panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let root = QuickAddView(onFinished: { [weak self] in self?.dismiss() })
            .environment(model)
            .modelContainer(container)
        let host = NSHostingController(rootView: root)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Quick Add to Stow"
        panel.identifier = NSUserInterfaceItemIdentifier("stow-quick-add-panel")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentViewController = host
        panel.delegate = self
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        panel?.delegate = nil
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}

@MainActor
private final class ClipboardMonitor: NSObject {
    enum CapturedContent {
        case draft(CaptureDraft)
        case attachment(CaptureDraft, fileURL: URL)
    }

    var captureHandler: ((CapturedContent) -> Void)?
    var statusHandler: ((String) -> Void)?
    var errorHandler: ((Error) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount = 0

    var statusText: String {
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .default: return "Permission not requested"
            case .ask: return "Needs Always Allow"
            case .alwaysAllow: return "Always Allow"
            case .alwaysDeny: return "Blocked by macOS"
            @unknown default: return "Unknown"
            }
        } else {
            return "Monitoring"
        }
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.35, target: self, selector: #selector(checkForChanges), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        statusHandler?(statusText)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func checkForChanges() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        statusHandler?(statusText)
        if #available(macOS 15.4, *) {
            switch pasteboard.accessBehavior {
            case .ask, .alwaysDeny:
                return
            case .default, .alwaysAllow:
                break
            @unknown default:
                return
            }
        }
        guard pasteboard.availableType(from: [.stowOwnedContent]) == nil else { return }

        do {
            try captureCurrentContent(sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName)
        } catch {
            errorHandler?(error)
        }
        statusHandler?(statusText)
    }

    private func captureCurrentContent(sourceApp: String?) throws {
        let pastedURL = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL
        if let pastedURL, pastedURL.isFileURL {
            try captureFile(at: pastedURL, sourceApp: sourceApp)
            return
        }

        if let image = NSImage(pasteboard: pasteboard), let tiffData = image.tiffRepresentation {
            let representation = NSBitmapImageRep(data: tiffData)
            let data = representation?.representation(using: .png, properties: [:]) ?? tiffData
            let fileExtension = representation == nil ? "tiff" : "png"
            let contentType = representation == nil ? UTType.tiff.identifier : UTType.png.identifier
            let fileURL = try stage(data: data, fileName: "Clipboard Image.\(fileExtension)")
            let draft = CaptureDraft(
                type: .image,
                title: "Clipboard Image",
                stagedAttachmentName: fileURL.lastPathComponent,
                attachmentByteCount: data.count,
                contentType: contentType,
                fileName: fileURL.lastPathComponent,
                sourceApp: sourceApp
            )
            captureHandler?(.attachment(draft, fileURL: fileURL))
            return
        }

        if let string = pasteboard.string(forType: .string) {
            captureText(string, sourceApp: sourceApp)
            return
        }

        if let pastedURL, !pastedURL.isFileURL {
            captureText(pastedURL.absoluteString, sourceApp: sourceApp)
        }
    }

    private func captureText(_ string: String, sourceApp: String?) {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let components = URLComponents(string: value)
        let scheme = components?.scheme?.lowercased()
        let isWebURL = (scheme == "http" || scheme == "https") && components?.host?.isEmpty == false
        let draft = CaptureDraft(
            type: isWebURL ? .link : .text,
            title: "",
            textContent: isWebURL ? nil : value,
            urlString: isWebURL ? value : nil,
            sourceApp: sourceApp
        )
        captureHandler?(.draft(draft))
    }

    private func captureFile(at sourceURL: URL, sourceApp: String?) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true else { return }
        let byteCount = values.fileSize ?? 0
        guard byteCount <= 100 * 1_024 * 1_024 else { throw CaptureValidationError.attachmentTooLarge }

        let fileName = sourceURL.lastPathComponent.isEmpty ? "Clipboard File" : sourceURL.lastPathComponent
        let stagedURL = try stageFile(at: sourceURL, fileName: fileName)
        let type: ItemType = values.contentType?.conforms(to: .image) == true ? .image : .file
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let draft = CaptureDraft(
            type: type,
            title: title,
            stagedAttachmentName: stagedURL.lastPathComponent,
            attachmentByteCount: byteCount,
            contentType: values.contentType?.identifier,
            fileName: fileName,
            sourceApp: sourceApp
        )
        captureHandler?(.attachment(draft, fileURL: stagedURL))
    }

    private func stage(data: Data, fileName: String) throws -> URL {
        guard data.count <= 100 * 1_024 * 1_024 else { throw CaptureValidationError.attachmentTooLarge }
        let directory = try stagingDirectory()
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func stageFile(at sourceURL: URL, fileName: String) throws -> URL {
        let directory = try stagingDirectory()
        let fileURL = directory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: fileURL)
        return fileURL
    }

    private func stagingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
