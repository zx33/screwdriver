import AppKit
import SwiftUI
import Combine
import StatsCore

@main
enum MacStatsBarMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private lazy var trayController = TrayController(model: model)
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MacStatsBar.Entry"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Mac Stats Bar")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(togglePrimary)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Mac Stats Bar 系统状态与 Codex 额度")
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        trayController.openDashboard = { [weak self] settings in self?.showDashboard(settings: settings) }
        trayController.onVisibilityChanged = { [weak self] _ in self?.updateStatus() }
        model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updateStatus() }.store(in: &subscriptions)
        model.settings.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updateStatus() }.store(in: &subscriptions)
        model.settings.$trayEnabled.removeDuplicates().dropFirst().sink { [weak self] enabled in
            if !enabled {
                self?.trayController.dismiss(handoff: true)
                self?.trayController.tray.stopOrganizing()
            }
        }.store(in: &subscriptions)
        model.start()
        updateStatus()
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstLaunch || CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.togglePrimary() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown && !trayController.isShown { togglePrimary() }
        return true
    }

    private func updateStatus() {
        let compact = model.settings.trayEnabled && model.settings.compactMenu
        item?.button?.title = compact || model.menuTitle.isEmpty ? "" : " " + model.menuTitle
        let symbol = model.settings.trayEnabled ? (trayController.isShown ? "chevron.up" : "chevron.down") : "waveform.path"
        item?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Mac Stats Bar")
        item?.button?.image?.isTemplate = true
        item?.button?.setAccessibilityLabel(model.settings.trayEnabled ? "展开或收起 Mac Stats Bar 托盘" : "Mac Stats Bar 系统状态与 Codex 额度")
        item?.button?.toolTip = "Mac Stats Bar\n\(model.menuTitle)\n\(model.updatedLabel)\(model.isUsageStale ? " · 额度可能已过期" : "")"
        item?.button?.appearsDisabled = model.isPaused
    }

    @objc private func togglePrimary() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            trayController.dismiss()
            if popover.isShown { popover.performClose(nil) } else { showDashboard() }
            return
        }
        if model.settings.trayEnabled {
            popover.performClose(nil)
            if let button = item?.button { trayController.toggle(relativeTo: button) }
        } else {
            trayController.dismiss()
            trayController.tray.stopOrganizing()
            if popover.isShown { popover.performClose(nil) } else { showDashboard() }
        }
    }

    private func showDashboard(settings: Bool = false) {
        guard let button = item.button else { return }
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model, settings: model.settings, showingSettings: settings))
        popover.contentSize = NSSize(width: 388, height: 660)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        // Release charts and view timers while the panel is hidden.
        popover.contentViewController = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        popover.performClose(nil)
        trayController.shutdown()
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

enum Diagnostics {
    static func run() {
        let sampler = SystemSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1)
        let system = sampler.sample()
        var report: [String: Any] = [
            "sampledAt": ISO8601DateFormatter().string(from: system.timestamp),
            "cpuPercent": system.cpuPercent as Any? ?? NSNull(),
            "memoryUsedBytes": system.memory?.used as Any? ?? NSNull(),
            "memoryTotalBytes": system.memory?.total as Any? ?? NSNull(),
            "downloadBytesPerSecond": system.network?.download as Any? ?? NSNull(),
            "uploadBytesPerSecond": system.network?.upload as Any? ?? NSNull(),
            "diskAvailableBytes": system.disk?.available as Any? ?? NSNull(),
            "batteryPercent": system.battery?.percent as Any? ?? NSNull(),
            "thermalState": system.thermalLabel
        ]
        do {
            guard let executable = CodexExecutable.locate() else { throw CodexClientError.missingExecutable }
            let reading = try CodexUsageClient(executableURL: executable).read()
            report["codexReadSucceeded"] = true
            report["quotaBuckets"] = reading.snapshot.buckets.map { id, bucket -> [String: Any] in
                ["name": bucket.displayName(fallback: id), "windows": bucket.windows.map { _, window -> [String: Any] in
                    ["period": window.title, "remainingPercent": window.remainingPercent as Any? ?? NSNull(),
                     "resetsAt": window.resetDate.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull()]
                }]
            }
            report["resetCardsAvailable"] = reading.snapshot.rateLimitResetCredits?.count as Any? ?? NSNull()
        } catch {
            report["codexReadSucceeded"] = false
            report["error"] = error.localizedDescription
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        if report["codexReadSucceeded"] as? Bool != true { exit(1) }
    }
}
