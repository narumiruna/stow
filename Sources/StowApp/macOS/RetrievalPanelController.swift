import AppKit
import Combine
import SwiftData
import SwiftUI
import StowCore

@MainActor
struct QuickPanelSettingsAction {
    let perform: () -> Void
}

@MainActor
enum RetrievalUseKind {
    case defaultPaste
    case copy
    case open
}

@MainActor
final class RetrievalPanelSession: ObservableObject {
    @Published var panelHeight: CGFloat = 340
    @Published var panelWidth: CGFloat = 980
    @Published var feedback: String?
    @Published var isVisible = false
    @Published var previewGeneration = 0
    @Published var acceptsPreviewShortcut = false
    @Published var directPasteAvailable = false
    @Published var isDragging = false
    @Published var closeCommand: QuickPanelCloseCommand?
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
    private struct PendingClose {
        let id: UUID
        let returnFocus: Bool
        let afterClose: (() -> Void)?
    }

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
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var pendingClose: PendingClose?
    private var settingsAction: (() -> Void)?
    private var menuTrackingDepth = 0
    private var menuTrackingEndedAt = Date.distantPast

    var destinationHandler: ((QuickPanelDestination) -> Void)?
    var isVisible: Bool { panel?.isVisible == true }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func screenParametersDidChange() { repositionForScreenChange() }
    @objc private func applicationDidResignActive() {
        guard isVisible, !shouldDeferOutsideClick else { return }
        if NSEvent.pressedMouseButtons != 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.isVisible, !self.shouldDeferOutsideClick else { return }
                self.requestClose(.outsideClick)
            }
        } else {
            requestClose(.outsideClick)
        }
    }
    @objc private func menuDidBeginTracking(_ notification: Notification) { menuTrackingDepth += 1 }
    @objc private func menuDidEndTracking(_ notification: Notification) {
        menuTrackingDepth = max(0, menuTrackingDepth - 1)
        menuTrackingEndedAt = Date()
    }

    func present(model: AppModel, container: ModelContainer) {
        let now = Date()
        guard now.timeIntervalSince(lastPresentationRequest) > 0.35 else { return }
        lastPresentationRequest = now
        self.model = model
        if panel?.isVisible == true {
            requestClose(.shortcutToggle)
            return
        }

        targetApplication = previousApplication()
        guard let screen = RetrievalPanelGeometry.screen() ?? NSScreen.main else { return }
        activeScreen = screen
        let height = requestedInitialHeight(on: screen)
        let frame = requestedFrame(on: screen, height: height)
        session.panelHeight = height
        session.panelWidth = frame.width
        session.feedback = nil
        session.directPasteAvailable = directPasteService.canPasteDirectly && targetApplication != nil

        if panel == nil {
            createPanel(model: model, container: container)
        }
        guard let panel else { return }
        panel.setFrame(frame, display: true)
        panel.minSize = NSSize(width: min(480, panel.frame.width), height: RetrievalPanelGeometry.minimumHeight)
        panel.maxSize = NSSize(width: screen.visibleFrame.width, height: screen.visibleFrame.height * 0.6)
        if isUITesting && !preservesFrontmostApplicationDuringUITest {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installKeyMonitor()
        installOutsideClickMonitors()
        session.isVisible = true
    }

    func requestClose(_ request: QuickPanelCloseRequest) {
        let returnFocus: Bool
        let afterClose: (() -> Void)?
        switch request {
        case .destination(let destination):
            returnFocus = false
            if destination == .settings, let settingsAction {
                afterClose = settingsAction
            } else {
                afterClose = { [weak self] in self?.destinationHandler?(destination) }
            }
        case .outsideClick:
            returnFocus = false
            afterClose = nil
        case .completedUse, .escape, .explicit, .shortcutToggle:
            returnFocus = true
            afterClose = nil
        }
        enqueueClose(request, returnFocus: returnFocus, afterClose: afterClose)
    }

    func approveClose(commandID: UUID) {
        guard let pendingClose, pendingClose.id == commandID else { return }
        let returnFocus = pendingClose.returnFocus
        let afterClose = pendingClose.afterClose
        self.pendingClose = nil
        dismiss(returnFocus: returnFocus)
        afterClose?()
    }

    func cancelClose(commandID: UUID) {
        guard pendingClose?.id == commandID else { return }
        pendingClose = nil
        session.closeCommand = nil
    }

    func dismiss(returnFocus: Bool = false) {
        feedbackGeneration = UUID()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor); self.globalPointerMonitor = nil }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor); self.localPointerMonitor = nil }
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        pendingClose = nil
        session.closeCommand = nil
        session.isVisible = false
        session.isDragging = false
        session.feedback = nil
        settingsAction = nil
        if returnFocus { activateTargetApplication() }
    }

    func resize(to requestedHeight: CGFloat, persist: Bool) {
        guard let panel, let screen = activeScreen ?? panel.screen else { return }
        let height = RetrievalPanelGeometry.clampedHeight(requestedHeight, on: screen)
        let visible = screen.visibleFrame
        let maximumWidth = max(320, visible.width - RetrievalPanelGeometry.outerMargin * 2)
        let minimumWidth = min(480, maximumWidth)
        var frame = panel.frame
        frame.origin.y = visible.minY + RetrievalPanelGeometry.outerMargin
        frame.size.height = height
        frame.size.width = min(max(frame.width, minimumWidth), maximumWidth)
        frame.origin.x = min(
            max(frame.minX, visible.minX + RetrievalPanelGeometry.outerMargin),
            visible.maxX - RetrievalPanelGeometry.outerMargin - frame.width
        )
        panel.setFrame(frame, display: true)
        session.panelHeight = height
        session.panelWidth = frame.width
        if persist { UserDefaults.standard.set(Double(height), forKey: heightDefaultsKey(for: screen)) }
    }

    func openLibrary() {
        if isVisible {
            requestClose(.destination(.library))
            return
        }
        presentLibrary()
    }

    func openSettings() {
        if isVisible {
            requestClose(.destination(.settings))
            return
        }
        presentSettings()
    }

    func presentLibrary() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = libraryWindow() {
            window.makeKeyAndOrderFront(nil)
        } else {
            createManagedLibraryWindow()
        }
    }

    func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let selector = Selector(("showSettingsWindow:"))
        if !NSApp.sendAction(selector, to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func createPanel(model: AppModel, container: ModelContainer) {
        let root = RetrievalPanelView(
            session: session,
            onRequestClose: { [weak self] request in self?.requestClose(request) },
            onApproveClose: { [weak self] commandID in self?.approveClose(commandID: commandID) },
            onCancelClose: { [weak self] commandID in self?.cancelClose(commandID: commandID) },
            onRegisterSettingsAction: { [weak self] registration in self?.settingsAction = registration.perform },
            onResize: { [weak self] height, persist in self?.resize(to: height, persist: persist) },
            onUse: { [weak self] item, attachment, kind in self?.use(item, attachment: attachment, kind: kind) }
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
        panel.animationBehavior = isUITesting ? .none : .utilityWindow
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
                enqueueClose(.completedUse, returnFocus: false) { [weak self] in
                    self?.directPasteService.paste(into: target)
                }
            } else {
                showFeedback("Copied — paste with Command-V", thenDismiss: true)
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
            if opened { enqueueClose(.completedUse, returnFocus: false) }
        }
    }

    private func enqueueClose(
        _ request: QuickPanelCloseRequest,
        returnFocus: Bool,
        afterClose: (() -> Void)? = nil
    ) {
        guard isVisible, pendingClose == nil else { return }
        let command = QuickPanelCloseCommand(id: UUID(), request: request)
        pendingClose = PendingClose(id: command.id, returnFocus: returnFocus, afterClose: afterClose)
        session.closeCommand = command
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
                    self.requestClose(.escape)
                    return true
                }
                guard self.session.acceptsPreviewShortcut else { return false }
                self.session.previewGeneration += 1
                return true
            }
            return handled ? nil : event
        }
    }

    private func installOutsideClickMonitors() {
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible, !self.shouldDeferOutsideClick else { return }
                self.requestClose(.outsideClick)
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            let shouldRequestClose = MainActor.assumeIsolated {
                guard let self, self.isVisible, !self.shouldDeferOutsideClick,
                      let eventWindow = event.window,
                      eventWindow !== self.panel,
                      !self.isTransientWindow(eventWindow) else { return false }
                return true
            }
            if shouldRequestClose {
                Task { @MainActor [weak self] in self?.requestClose(.outsideClick) }
            }
            return event
        }
    }

    private var shouldDeferOutsideClick: Bool {
        session.isDragging || menuTrackingDepth > 0 || Date().timeIntervalSince(menuTrackingEndedAt) < 0.15 || hasVisibleTransientWindow
    }

    private var hasVisibleTransientWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible && window !== panel && isTransientWindow(window)
        }
    }

    private func isTransientWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        let className = String(describing: type(of: window))
        return window.level == .popUpMenu || className.contains("Menu") || className.contains("Popover")
    }

    private func showFeedback(_ message: String, thenDismiss: Bool = false) {
        let generation = UUID()
        feedbackGeneration = generation
        session.feedback = message
        DispatchQueue.main.asyncAfter(deadline: .now() + (thenDismiss ? 1.6 : 1.4)) { [weak self] in
            guard let self, self.feedbackGeneration == generation else { return }
            self.session.feedback = nil
            if thenDismiss { self.requestClose(.completedUse) }
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

    private var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    private var preservesFrontmostApplicationDuringUITest: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-frontmost-application")
        #else
        false
        #endif
    }

    private var requestedDarkAppearance: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AppleInterfaceStyle"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1].localizedCaseInsensitiveCompare("Dark") == .orderedSame
    }

    private func requestedFrame(on screen: NSScreen, height: CGFloat) -> NSRect {
        var frame = RetrievalPanelGeometry.frame(on: screen, height: height)
        #if DEBUG
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-testing-panel-width=") }),
              let value = Double(argument.split(separator: "=").last ?? "") else { return frame }
        let width = min(max(CGFloat(value), 480), frame.width)
        frame.origin.x = screen.visibleFrame.midX - width / 2
        frame.size.width = width
        #endif
        return frame
    }

    private func requestedInitialHeight(on screen: NSScreen?) -> CGFloat {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-testing-panel-height=") }),
           let value = Double(argument.split(separator: "=").last ?? "") {
            return screen.map { RetrievalPanelGeometry.clampedHeight(CGFloat(value), on: $0) } ?? CGFloat(value)
        }
        #endif
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
        guard let panel, panel.isVisible,
              let screen = RetrievalPanelGeometry.screen() ?? activeScreen ?? NSScreen.main else { return }
        activeScreen = screen
        let visible = screen.visibleFrame
        let height = RetrievalPanelGeometry.clampedHeight(session.panelHeight, on: screen)
        let maximumWidth = max(320, visible.width - RetrievalPanelGeometry.outerMargin * 2)
        let width = min(max(panel.frame.width, min(480, maximumWidth)), maximumWidth)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.minY + RetrievalPanelGeometry.outerMargin,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
        session.panelHeight = height
        session.panelWidth = width
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
        session.panelWidth = panel.frame.width
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === self.panel else { return }
        resize(to: panel.frame.height, persist: true)
    }
}
