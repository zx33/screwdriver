import AppKit
import ApplicationServices
import Combine
import StatsCore

struct MenuExtra: Identifiable {
    let id: String
    let appName: String
    let label: String
    let icon: NSImage?
    let handle: ExtraHandle
    let actions: Set<String>
    let position: CGPoint
}

/// AX references are immutable handles. All messaging stays on the serial
/// worker; only opaque handles cross back to the main actor with scan results.
final class ExtraHandle: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

private struct ExtraProcess: Sendable {
    let pid: pid_t
    let bundleID: String
    let name: String
}

private struct DiscoveredExtra: Sendable {
    let id: String
    let pid: pid_t
    let appName: String
    let label: String
    let handle: ExtraHandle
    let actions: Set<String>
    let position: CGPoint
}

private final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

/// Only reads the accessibility surface for status items. No screen capture,
/// private WindowServer API, input event synthesis or app-launch substitution.
private enum MenuExtrasReader {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let text = value(element, attribute) as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(140))
    }

    static func scan(_ processes: [ExtraProcess], cancellation: ScanCancellation) -> (items: [DiscoveredExtra], partial: Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        var items: [DiscoveredExtra] = []
        for process in processes {
            guard !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return (items, true) }
            let app = AXUIElementCreateApplication(process.pid)
            AXUIElementSetMessagingTimeout(app, 0.12)
            var barValue = value(app, kAXExtrasMenuBarAttribute)
            if barValue == nil && ["com.apple.controlcenter", "com.apple.systemuiserver"].contains(process.bundleID) {
                barValue = value(app, kAXMenuBarAttribute)
            }
            guard let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() else { continue }
            let bar = unsafeBitCast(barValue, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(bar, 0.12)
            guard let children = value(bar, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            for (index, child) in children.prefix(80).enumerated() {
                guard !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return (items, true) }
                AXUIElementSetMessagingTimeout(child, 0.12)
                guard string(child, kAXRoleAttribute) == kAXMenuBarItemRole else { continue }
                var actionNames: CFArray?
                AXUIElementCopyActionNames(child, &actionNames)
                let actions = Set(actionNames as? [String] ?? [])
                guard actions.contains(kAXPressAction) || actions.contains(kAXShowMenuAction) else { continue }
                let label = string(child, kAXDescriptionAttribute)
                    ?? string(child, kAXTitleAttribute) ?? process.name
                let key = string(child, kAXIdentifierAttribute) ?? "item-\(index)"
                var point = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
                if let position = value(child, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
                }
                items.append(DiscoveredExtra(id: "\(process.bundleID):\(key)", pid: process.pid, appName: process.name,
                                       label: label, handle: ExtraHandle(child),
                                       actions: actions, position: point))
            }
        }
        return (items.sorted {
            ($0.position.x.isFinite ? $0.position.x : .infinity) < ($1.position.x.isFinite ? $1.position.x : .infinity)
        }, false)
    }
}

@MainActor
final class TrayModel: ObservableObject {
    @Published private(set) var extras: [MenuExtra] = []
    @Published private(set) var hasAccess = AXIsProcessTrusted()
    @Published private(set) var isScanning = false
    @Published private(set) var connected = UserDefaults.standard.bool(forKey: "trayConnectExtras")
    @Published var search = ""
    @Published var message: String?
    @Published private var collection = TrayCollectionState()
    @Published private(set) var originalsHidden = false
    var onOpenExtra: ((MenuExtra, String) -> Void)?

    var organizerEnabled: Bool { collection.isEnabled }
    var isArranging: Bool { collection.isArranging }
    var collectedIDs: Set<String> { collection.collectedIDs }

    private let worker = DispatchQueue(label: "local.macstatsbar.menu-extras", qos: .userInitiated)
    private var generation = 0
    private var scanCancellation: ScanCancellation?
    private var iconsByPID: [pid_t: NSImage] = [:]
    private var savedOrder = UserDefaults.standard.stringArray(forKey: "trayItemOrder") ?? []
    private var divider: NSStatusItem?
    private weak var anchor: NSStatusBarButton?
    private var isSleeping = false
    private var restorationTask: Task<Void, Never>?

    var collectedExtras: [MenuExtra] {
        organizerEnabled && !isArranging ? extras.filter { collectedIDs.contains($0.id) } : extras
    }

    var visibleExtras: [MenuExtra] {
        let ids = TrayOrder.arrange(collectedExtras.map(\.id), saved: savedOrder)
        let lookup = Dictionary(extras.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { lookup[$0] }.filter {
            search.isEmpty || "\($0.label) \($0.appName)".localizedCaseInsensitiveContains(search)
        }
    }

    func refresh(completion: (() -> Void)? = nil) {
        hasAccess = AXIsProcessTrusted()
        guard connected, hasAccess else {
            cancelScan()
            extras = []
            iconsByPID = [:]
            if !hasAccess { stopOrganizing() }
            return
        }
        guard !isScanning else { return }
        message = nil
        isScanning = true
        generation += 1
        let ticket = generation
        let apps = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        let processes = apps
            .map { ExtraProcess(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "pid-\($0.processIdentifier)",
                                name: $0.localizedName ?? "菜单栏应用") }
        let cancellation = ScanCancellation()
        scanCancellation = cancellation
        worker.async { [weak self] in
            let result = MenuExtrasReader.scan(processes, cancellation: cancellation)
            DispatchQueue.main.async { [weak self] in
                guard let self, ticket == self.generation else { return }
                self.iconsByPID = [:]
                for pid in Set(result.items.map(\.pid)) {
                    self.iconsByPID[pid] = NSRunningApplication(processIdentifier: pid)?.icon
                }
                self.extras = result.items.map {
                    MenuExtra(id: $0.id, appName: $0.appName, label: $0.label, icon: self.iconsByPID[$0.pid],
                              handle: $0.handle, actions: $0.actions, position: $0.position)
                }
                self.isScanning = false
                self.scanCancellation = nil
                if result.partial { self.message = "部分应用响应较慢，可再次刷新。" }
                if !result.partial { completion?() }
            }
        }
    }

    func connect() {
        connected = true
        UserDefaults.standard.set(true, forKey: "trayConnectExtras")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccess = AXIsProcessTrustedWithOptions(options)
        if hasAccess { refresh() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func disconnect() {
        connected = false
        UserDefaults.standard.set(false, forKey: "trayConnectExtras")
        cancelScan()
        extras = []
        iconsByPID = [:]
        stopOrganizing()
    }

    func cancelScan() {
        scanCancellation?.cancel()
        scanCancellation = nil
        generation += 1
        isScanning = false
    }

    func move(_ extra: MenuExtra, by offset: Int) {
        var ids = TrayOrder.arrange(extras.map(\.id), saved: savedOrder)
        guard let index = ids.firstIndex(of: extra.id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        savedOrder = ids
        UserDefaults.standard.set(ids, forKey: "trayItemOrder")
        objectWillChange.send()
    }

    func perform(_ extra: MenuExtra, action: String, completion: @escaping (Bool) -> Void) {
        guard hasAccess, connected, extra.actions.contains(action) else { completion(false); return }
        worker.async { [handle = extra.handle] in
            AXUIElementSetMessagingTimeout(handle.element, 1)
            let result = AXUIElementPerformAction(handle.element, action as CFString)
            DispatchQueue.main.async { completion(result == .success) }
        }
    }

    func startOrganizing(anchor: NSStatusBarButton) {
        cancelRestoration()
        collection.beginArrangement()
        revealOriginals()
        guard divider == nil else { return }
        self.anchor = anchor
        let item = NSStatusBar.system.statusItem(withLength: 18)
        item.autosaveName = "MacStatsBar.TrayDivider"
        item.button?.title = "│"
        item.button?.toolTip = "按住 ⌘，把想收起的图标拖到这条线左侧"
        item.button?.setAccessibilityLabel("托盘收纳分隔线")
        divider = item
    }

    func finishOrganizing() {
        guard organizerEnabled, isArranging else { return }
        // Cmd-drag changes positions while the tray is closed. Read their new
        // positions before choosing which buttons belong in the collected area.
        cancelScan()
        refresh { [weak self] in
            guard let self, self.isArranging, let edge = self.divider?.button?.window?.frame.minX else { return }
            let ids = Set(self.extras.filter { $0.position.x < edge }.map(\.id))
            guard !ids.isEmpty else {
                self.message = "分隔线左侧还没有可收纳的图标。按住 ⌘ 拖入图标后，再点击完成。"
                return
            }
            if self.collapseOriginals() {
                self.collection.finishArrangement(collecting: ids)
                self.search = ""
            }
        }
    }

    func toggleOriginals() {
        cancelRestoration()
        collection.resume()
        if originalsHidden {
            collection.setCollapsed(false)
            revealOriginals()
        } else if collapseOriginals() {
            collection.setCollapsed(true)
        }
    }

    @discardableResult
    private func collapseOriginals(reportFailure: Bool = true) -> Bool {
        if originalsHidden { return true }
        guard let divider, let dividerWindow = divider.button?.window,
              let anchorWindow = anchor?.window, let screen = anchorWindow.screen,
              dividerWindow.screen == screen,
              TrayLayout.canCollapse(divider: dividerWindow.frame, anchor: anchorWindow.frame, screen: screen.frame) else {
            if reportFailure { message = "请按住 ⌘，把分隔线放到托盘箭头左侧，再收起图标。" }
            return false
        }
        divider.button?.title = ""
        divider.length = 10_000
        originalsHidden = true
        return true
    }

    private func revealOriginals() {
        divider?.length = 18
        divider?.button?.title = "│"
        originalsHidden = false
    }

    func didDismiss() {
        cancelScan()
        if collection.shouldCollapse, !originalsHidden { collapseOriginals() }
    }

    func revealForMenu() {
        // A pending wake-up retry must not collapse underneath a foreign menu.
        cancelRestoration()
        collection.resume()
        revealOriginals()
    }

    func prepareForSleep() {
        isSleeping = true
        cancelRestoration()
        cancelScan()
        collection.suspend()
        revealOriginals()
    }

    func resumeAfterWake() {
        isSleeping = false
        restoreAfterScreenChange()
    }

    func restoreAfterScreenChange() {
        cancelRestoration()
        cancelScan()
        guard organizerEnabled else { return }
        collection.suspend()
        // Keep the same NSStatusItem: removing it loses the user's boundary.
        revealOriginals()
        guard !isSleeping else { return }
        restorationTask = Task { @MainActor [weak self] in
            // Screen notifications can precede menu-bar layout. Coalesce them
            // and retry for at most 8.75 s, with no permanent polling or AX scan.
            for delay in [750, 500, 1_000, 2_000, 4_000] {
                do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
                catch { return }
                guard let self, !Task.isCancelled, self.organizerEnabled, !self.isSleeping else { return }
                if !self.collection.prefersCollapsed || self.collapseOriginals(reportFailure: false) {
                    self.collection.resume()
                    self.restorationTask = nil
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.restorationTask = nil
            self.message = "收纳范围已保留。菜单栏位置尚未恢复，可从更多菜单收起图标，或点击「重新整理」。"
        }
    }

    private func cancelRestoration() {
        restorationTask?.cancel()
        restorationTask = nil
    }

    func stopOrganizing() {
        cancelRestoration()
        collection.stop()
        revealOriginals()
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        divider = nil
    }

    func shutdown() {
        cancelScan()
        stopOrganizing()
    }
}
