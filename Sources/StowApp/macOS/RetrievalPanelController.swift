import AppKit
import Combine
import SwiftData
import SwiftUI
import StowCore

@MainActor
enum RetrievalUseKind {
    case defaultPaste
    case copy
    case open
}

@MainActor
final class RetrievalPanelSession: ObservableObject {
    @Published var panelHeight: CGFloat = 340
    @Published var feedback: String?
    @Published var isVisible = false
    @Published var previewGeneration = 0
    @Published var acceptsPreviewShortcut = false
    @Published var escapeGeneration = 0
}

@MainActor
struct RetrievalPanelGeometry {
    static let outerMargin: CGFloat = 14
    static let minimumHeight: CGFloat = 210
    static let defaultHeight: CGFloat = 340

    static func screen(at point: NSPoint = NSEvent.mouseLocation, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? screens.first
    }

    static func clampedHeight(_ requested: CGFloat, on screen: NSScreen) -> CGFloat {
        min(max(requested, minimumHeight), max(minimumHeight, screen.visibleFrame.height * 0.6))
    }

    static func frame(on screen: NSScreen, height requestedHeight: CGFloat) -> NSRect {
        let visible = screen.visibleFrame
        let height = clampedHeight(requestedHeight, on: screen)
        return NSRect(
            x: visible.minX + outerMargin,
            y: visible.minY + outerMargin,
            width: max(320, visible.width - outerMargin * 2),
            height: height
        )
    }
}

@MainActor
final class StowRetrievalPanel: NSPanel {
    var previewHandler: (() -> Void)?
    var previewEnabled: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, event.keyCode == 49, modifiers.isEmpty, previewEnabled?() == true {
            previewHandler?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class RetrievalPanelController: NSObject, NSWindowDelegate {
    private var panel: StowRetrievalPanel?
    private let session = RetrievalPanelSession()
    private let directPasteService = DirectPasteService()
    private weak var model: AppModel?
    private var targetApplication: NSRunningApplication?
    private var activeScreen: NSScreen?
    private var managedLibraryWindow: NSWindow?
    private var feedbackGeneration = UUID()
    private var lastPresentationRequest = Date.distantPast
    private var keyMonitor: Any?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange() { repositionForScreenChange() }

    func present(model: AppModel, container: ModelContainer) {
        let now = Date()
        guard now.timeIntervalSince(lastPresentationRequest) > 0.35 else { return }
        lastPresentationRequest = now
        self.model = model
        if panel?.isVisible == true {
            dismiss(returnFocus: true)
            return
        }

        targetApplication = previousApplication()
        let screen = RetrievalPanelGeometry.screen() ?? NSScreen.main
        activeScreen = screen
        let height = requestedInitialHeight(on: screen)
        session.panelHeight = height
        session.feedback = nil

        if panel == nil {
            createPanel(model: model, container: container)
        }
        guard let panel, let screen else { return }
        panel.setFrame(RetrievalPanelGeometry.frame(on: screen, height: height), display: true)
        panel.minSize = NSSize(width: min(480, panel.frame.width), height: RetrievalPanelGeometry.minimumHeight)
        panel.maxSize = NSSize(width: screen.visibleFrame.width, height: screen.visibleFrame.height * 0.6)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { NSApp.activate(ignoringOtherApps: true) }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        session.isVisible = true
    }

    func dismiss(returnFocus: Bool = false) {
        feedbackGeneration = UUID()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        session.isVisible = false
        session.feedback = nil
        if returnFocus { activateTargetApplication() }
    }

    func resize(to requestedHeight: CGFloat, persist: Bool) {
        guard let panel, let screen = activeScreen ?? panel.screen else { return }
        let height = RetrievalPanelGeometry.clampedHeight(requestedHeight, on: screen)
        var frame = panel.frame
        frame.origin.y = screen.visibleFrame.minY + RetrievalPanelGeometry.outerMargin
        frame.size.height = height
        frame.size.width = max(320, screen.visibleFrame.width - RetrievalPanelGeometry.outerMargin * 2)
        frame.origin.x = screen.visibleFrame.minX + RetrievalPanelGeometry.outerMargin
        panel.setFrame(frame, display: true)
        session.panelHeight = height
        if persist { UserDefaults.standard.set(Double(height), forKey: heightDefaultsKey(for: screen)) }
    }

    func openLibrary() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        if let window = libraryWindow() {
            window.makeKeyAndOrderFront(nil)
        } else {
            createManagedLibraryWindow()
        }
    }

    private func createPanel(model: AppModel, container: ModelContainer) {
        let root = RetrievalPanelView(
            session: session,
            onDismiss: { [weak self] returnFocus in self?.dismiss(returnFocus: returnFocus) },
            onResize: { [weak self] height, persist in self?.resize(to: height, persist: persist) },
            onUse: { [weak self] item, attachment, kind in self?.use(item, attachment: attachment, kind: kind) },
            onOpenLibrary: { [weak self] in self?.openLibrary() },
            onQuickAdd: {
                NotificationCenter.default.post(name: .stowShowQuickAdd, object: nil)
            }
        )
        .environment(model)
        .modelContainer(container)

        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.setAccessibilityIdentifier("stow-retrieval-panel-content")

        let panel = StowRetrievalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: RetrievalPanelGeometry.defaultHeight),
            styleMask: [.titled, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Stow Quick Panel"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.identifier = NSUserInterfaceItemIdentifier("stow-retrieval-panel")
        panel.setAccessibilityElement(true)
        panel.setAccessibilityEnabled(true)
        panel.setAccessibilityRole(.window)
        panel.setAccessibilitySubrole(.standardWindow)
        panel.setAccessibilityTitle("Stow Quick Panel")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.backgroundColor = .clear
        if requestedDarkAppearance { panel.appearance = NSAppearance(named: .darkAqua) }
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .none : .utilityWindow
        panel.contentViewController = hosting
        panel.delegate = self
        panel.previewHandler = { [weak self] in self?.session.previewGeneration += 1 }
        panel.previewEnabled = { [weak self] in self?.session.acceptsPreviewShortcut == true }
        self.panel = panel
    }

    private func use(_ item: StowItem, attachment: StowAttachment?, kind: RetrievalUseKind) {
        guard let model else { return }
        switch kind {
        case .defaultPaste:
            let copied = model.performUse(item, action: .copy, metric: .itemCopied) {
                try PlatformActions.copy(item, attachmentData: attachment?.data, attachment: attachment)
            }
            guard copied else { return }
            if directPasteService.canPasteDirectly, targetApplication != nil {
                let target = targetApplication
                dismiss()
                directPasteService.paste(into: target)
            } else {
                showFeedback("Copied — enable Accessibility to paste directly", thenDismiss: true)
            }
        case .copy:
            let copied = model.performUse(item, action: .copy, metric: .itemCopied) {
                try PlatformActions.copy(item, attachmentData: attachment?.data, attachment: attachment)
            }
            if copied { showFeedback("Copied") }
        case .open:
            let opened = model.performUse(item, action: .open, metric: .itemOpened) {
                try PlatformActions.open(item, attachment: attachment)
            }
            if opened { dismiss() }
        }
    }

    private func installKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiersAreEmpty = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            let isUnmodifiedSpace = event.keyCode == 49 && modifiersAreEmpty
            let isUnmodifiedEscape = event.keyCode == 53 && modifiersAreEmpty
            guard isUnmodifiedSpace || isUnmodifiedEscape else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self, self.panel?.isVisible == true else { return false }
                if isUnmodifiedEscape {
                    self.session.escapeGeneration += 1
                    return true
                }
                guard self.session.acceptsPreviewShortcut else { return false }
                self.session.previewGeneration += 1
                return true
            }
            return handled ? nil : event
        }
    }

    private func showFeedback(_ message: String, thenDismiss: Bool = false) {
        let generation = UUID()
        feedbackGeneration = generation
        session.feedback = message
        DispatchQueue.main.asyncAfter(deadline: .now() + (thenDismiss ? 0.9 : 1.4)) { [weak self] in
            guard let self, self.feedbackGeneration == generation else { return }
            self.session.feedback = nil
            if thenDismiss { self.dismiss(returnFocus: true) }
        }
    }

    private func previousApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return application
    }

    private func activateTargetApplication() {
        guard let targetApplication, !targetApplication.isTerminated else { return }
        targetApplication.activate()
    }

    private var requestedDarkAppearance: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AppleInterfaceStyle"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1].localizedCaseInsensitiveCompare("Dark") == .orderedSame
    }

    private func requestedInitialHeight(on screen: NSScreen?) -> CGFloat {
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-testing-panel-height=") }),
           let value = Double(argument.split(separator: "=").last ?? "") {
            return screen.map { RetrievalPanelGeometry.clampedHeight(CGFloat(value), on: $0) } ?? CGFloat(value)
        }
        guard let screen else { return RetrievalPanelGeometry.defaultHeight }
        let stored = UserDefaults.standard.double(forKey: heightDefaultsKey(for: screen))
        return RetrievalPanelGeometry.clampedHeight(stored > 0 ? CGFloat(stored) : RetrievalPanelGeometry.defaultHeight, on: screen)
    }

    private func heightDefaultsKey(for screen: NSScreen) -> String {
        let name = screen.localizedName.replacingOccurrences(of: " ", with: "-")
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let number = (screen.deviceDescription[screenNumberKey] as? NSNumber)?.stringValue ?? "unknown"
        return "retrievalPanelHeight.\(name).\(number)"
    }

    private func repositionForScreenChange() {
        guard panel?.isVisible == true else { return }
        let screen = RetrievalPanelGeometry.screen() ?? activeScreen ?? NSScreen.main
        activeScreen = screen
        guard screen != nil else { return }
        resize(to: session.panelHeight, persist: false)
    }

    private func createManagedLibraryWindow() {
        guard let dependencies = MacAppCoordinator.dependencies else { return }
        let model = dependencies.model
        self.model = model
        let root = StowRootView()
            .environment(model)
            .modelContainer(dependencies.container)
            .frame(minWidth: 840, minHeight: 560)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Stow"
        window.identifier = NSUserInterfaceItemIdentifier("stow-library-window")
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.setFrameAutosaveName("StowLibraryWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        managedLibraryWindow = window
    }

    private func libraryWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) && window.canBecomeMain &&
                (window.identifier?.rawValue == "stow-library-window" || window.title == "Stow")
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === self.panel else { return }
        session.panelHeight = panel.frame.height
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === self.panel else { return }
        resize(to: panel.frame.height, persist: true)
    }
}
