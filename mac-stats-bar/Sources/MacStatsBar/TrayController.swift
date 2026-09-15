import AppKit
import SwiftUI
import StatsCore

private final class TrayPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

@MainActor
final class TrayController {
    let tray = TrayModel()
    var isShown: Bool { panel?.isVisible ?? false }
    var onVisibilityChanged: ((Bool) -> Void)?
    var openDashboard: ((Bool) -> Void)?

    private let model: AppModel
    private var panel: TrayPanel?
    private weak var anchor: NSStatusBarButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var sleepObserver: NSObjectProtocol?
    private var stopping = false

    init(model: AppModel) {
        self.model = model
        tray.onOpenExtra = { [weak self] extra, action in self?.open(extra, action: action) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.tray.stopOrganizing()
                self?.dismiss(handoff: true)
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.isShown == true { self?.tray.refresh() } }
        })
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.tray.stopOrganizing()
                self?.dismiss(handoff: true)
            }
        }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown { dismiss() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !stopping, model.settings.trayEnabled else { return }
        guard let screen = button.window?.screen ?? NSScreen.main else { return }
        anchor = button
        tray.search = ""
        if panel == nil {
            let panel = TrayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            panel.title = "Mac Stats Bar Preview · 收纳托盘"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onEscape = { [weak self] in self?.dismiss() }
            self.panel = panel
        }
        let view = TrayView(model: model, tray: tray, openDashboard: { [weak self] settings in
            self?.dismiss()
            self?.openDashboard?(settings)
        }, organize: { [weak self, weak button] in
            if let button { self?.tray.startOrganizing(anchor: button) }
        }, close: { [weak self] in self?.dismiss() })
        let frame = TrayLayout.frame(anchorX: button.window?.frame.midX ?? screen.visibleFrame.maxX,
                                     screen: screen.frame, visible: screen.visibleFrame,
                                     safeTop: screen.safeAreaInsets.top,
                                     size: CGSize(width: 560, height: 362))
        panel?.contentViewController = NSHostingController(rootView: view.frame(width: frame.width, height: frame.height))
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installDismissMonitors()
        tray.refresh()
        onVisibilityChanged?(true)
    }

    func dismiss(handoff: Bool = false) {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        removeDismissMonitors()
        if handoff { tray.cancelScan() } else { tray.didDismiss() }
        onVisibilityChanged?(false)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self.panel, event.window !== self.anchor?.window else { return event }
            self.dismiss()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func removeDismissMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func open(_ extra: MenuExtra, action: String) {
        // Restore the original area before the app opens its own menu. Keep it
        // visible until the next tray dismissal; never collapse under a menu.
        tray.revealOriginals()
        dismiss(handoff: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.stopping, self.model.settings.trayEnabled else { return }
            self.tray.perform(extra, action: action) { [weak self] succeeded in
                guard let self, !succeeded else { return }
                if let anchor = self.anchor { self.show(relativeTo: anchor) }
                self.tray.message = "该应用未响应菜单操作；原图标已展开，可直接点击。"
            }
        }
    }

    func shutdown() {
        stopping = true
        dismiss(handoff: true)
        tray.shutdown()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
