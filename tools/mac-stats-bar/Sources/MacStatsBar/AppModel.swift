import AppKit
import Combine
import ServiceManagement
import StatsCore

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var showCPU: Bool { didSet { defaults.set(showCPU, forKey: "showCPU") } }
    @Published var showMemory: Bool { didSet { defaults.set(showMemory, forKey: "showMemory") } }
    @Published var showCodex: Bool { didSet { defaults.set(showCodex, forKey: "showCodex") } }
    @Published var systemInterval: Double { didSet { defaults.set(systemInterval, forKey: "systemInterval") } }
    @Published var codexInterval: Double { didSet { defaults.set(codexInterval, forKey: "codexInterval") } }
    @Published var codexPath: String { didSet { defaults.set(codexPath, forKey: "codexPath") } }
    @Published var selectedBucket: String { didSet { defaults.set(selectedBucket, forKey: "selectedBucket") } }
    @Published var trayEnabled: Bool { didSet { defaults.set(trayEnabled, forKey: "trayEnabled") } }
    @Published var compactMenu: Bool { didSet { defaults.set(compactMenu, forKey: "compactMenu") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["showCPU": true, "showMemory": false, "showCodex": true,
                                     "systemInterval": 5.0, "codexInterval": 300.0, "selectedBucket": "codex",
                                     "trayEnabled": true, "compactMenu": true])
        showCPU = defaults.bool(forKey: "showCPU")
        showMemory = defaults.bool(forKey: "showMemory")
        showCodex = defaults.bool(forKey: "showCodex")
        let system = defaults.double(forKey: "systemInterval")
        systemInterval = [2.0, 5, 10].contains(system) ? system : 5
        let codex = defaults.double(forKey: "codexInterval")
        codexInterval = [60.0, 300, 600].contains(codex) ? codex : 300
        codexPath = defaults.string(forKey: "codexPath") ?? ""
        selectedBucket = defaults.string(forKey: "selectedBucket") ?? "codex"
        trayEnabled = defaults.bool(forKey: "trayEnabled")
        compactMenu = defaults.bool(forKey: "compactMenu")
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    @Published private(set) var system = SystemReading.empty
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var usage: UsageReading?
    @Published private(set) var usageError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPaused = false
    @Published private(set) var isSleeping = false
    @Published private(set) var nextRefresh: Date?
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginMessage: String?

    private let sampler = SystemSampler()
    private let systemQueue = DispatchQueue(label: "local.macstatsbar.sampling", qos: .utility)
    private var sampling = false
    private var systemTimer: Timer?
    private var usageTimer: Timer?
    private var usageTask: Task<Void, Never>?
    private var settingsSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var lastCodexPath = ""
    private var failures = 0
    private var stopping = false

    var selectedBucketID: String? {
        guard let snapshot = usage?.snapshot else { return nil }
        return snapshot.bucket(id: settings.selectedBucket) != nil ? settings.selectedBucket : snapshot.buckets.first?.id
    }
    var selectedQuota: QuotaBucket? {
        selectedBucketID.flatMap { usage?.snapshot.bucket(id: $0) }
    }
    var isUsageStale: Bool {
        usageError != nil || (usage?.isStale(at: Date(), refreshInterval: settings.codexInterval) ?? true)
    }
    var connectionLabel: String {
        if isRefreshing { return "同步中" }
        if usageError != nil { return usage == nil ? "未连接" : "同步失败" }
        if usage == nil { return "等待同步" }
        if isUsageStale { return "数据已过期" }
        return "已同步"
    }
    var updatedLabel: String {
        guard let date = usage?.fetchedAt else { return "尚未同步" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "刚刚同步" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前同步" }
        return "\(Int(seconds / 3_600)) 小时前同步"
    }
    var menuTitle: String {
        var parts: [String] = []
        if settings.showCPU { parts.append("CPU \(DisplayFormat.percent(system.cpuPercent))") }
        if settings.showMemory { parts.append("M \(DisplayFormat.percent(system.memory?.percent))") }
        if settings.showCodex {
            let value = DisplayFormat.percent(selectedQuota?.remainingPercent(at: Date()))
            let marker = usage != nil && isUsageStale && value != "—" ? "~" : ""
            parts.append("C \(marker)\(value)")
        }
        return parts.joined(separator: "  ·  ")
    }

    func start() {
        lastCodexPath = settings.codexPath
        settingsSubscription = settings.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                if self.lastCodexPath != self.settings.codexPath {
                    self.lastCodexPath = self.settings.codexPath
                    self.usage = nil
                    self.usageError = nil
                    self.usageTask?.cancel()
                }
                self.rescheduleSystem()
                self.scheduleUsage()
                self.objectWillChange.send()
            }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        })
        rescheduleSystem()
        refreshUsage()
    }

    private func rescheduleSystem() {
        systemTimer?.invalidate()
        guard !isPaused, !isSleeping, !stopping else { return }
        sampleSystem()
        let timer = Timer(timeInterval: settings.systemInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleSystem() }
        }
        timer.tolerance = settings.systemInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        systemTimer = timer
    }

    private func sampleSystem() {
        guard !sampling, !stopping else { return }
        sampling = true
        systemQueue.async { [weak self, sampler] in
            let reading = sampler.sample()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sampling = false
                guard !self.isPaused, !self.isSleeping, !self.stopping else { return }
                self.system = reading
                if let value = reading.cpuPercent { self.cpuHistory = Array((self.cpuHistory + [value]).suffix(60)) }
                if let value = reading.memory?.percent { self.memoryHistory = Array((self.memoryHistory + [value]).suffix(60)) }
            }
        }
    }

    func refreshUsage() {
        guard !isRefreshing, !isSleeping, !stopping else { return }
        usageTimer?.invalidate()
        nextRefresh = nil
        guard let executable = CodexExecutable.locate(customPath: settings.codexPath) else {
            usageError = CodexClientError.missingExecutable.localizedDescription
            scheduleUsage()
            return
        }
        isRefreshing = true
        let requestedPath = settings.codexPath
        usageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reading = try await CodexUsageClient(executableURL: executable).fetch()
                try Task.checkCancellation()
                if requestedPath == self.settings.codexPath {
                    self.usage = reading
                    self.usageError = nil
                    self.failures = 0
                }
            } catch is CancellationError {
                // Pausing, sleeping or changing the selected program cancels this read.
            } catch {
                self.usageError = error.localizedDescription
                self.failures = min(5, self.failures + 1)
            }
            self.isRefreshing = false
            self.usageTask = nil
            self.scheduleUsage()
        }
    }

    private func scheduleUsage() {
        usageTimer?.invalidate()
        nextRefresh = nil
        guard !isPaused, !isSleeping, !stopping, !isRefreshing else { return }
        let delay = max(settings.codexInterval, failures > 0 ? min(900, pow(2, Double(failures)) * 30) : 0)
        var date = Date().addingTimeInterval(delay)
        if failures == 0, let usage {
            // Read again just after a future window reset or known card expiry.
            let resets = usage.snapshot.buckets.flatMap { $0.value.windows.compactMap { $0.value.resetDate } }
            let expiries = usage.snapshot.rateLimitResetCredits?.credits?.compactMap(\.expiryDate) ?? []
            if let deadline = (resets + expiries).filter({ $0 > Date() }).min() {
                date = min(date, max(Date().addingTimeInterval(15), deadline.addingTimeInterval(3)))
            }
        }
        nextRefresh = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        usageTimer = timer
    }

    func togglePaused() {
        isPaused.toggle()
        if isPaused {
            systemTimer?.invalidate(); usageTimer?.invalidate(); nextRefresh = nil
            usageTask?.cancel()
        } else {
            systemQueue.async { [sampler] in sampler.resetBaseline() }
            rescheduleSystem()
            refreshUsage()
        }
    }

    private func suspend() {
        isSleeping = true
        systemTimer?.invalidate(); usageTimer?.invalidate(); nextRefresh = nil
        usageTask?.cancel()
    }

    private func resume() {
        isSleeping = false
        systemQueue.async { [sampler] in sampler.resetBaseline() }
        cpuHistory = []; memoryHistory = []
        rescheduleSystem()
        if !isPaused { refreshUsage() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 登录项中允许启动。" : nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = "无法更改登录项。请先将应用移到「应用程序」文件夹。"
        }
    }

    func shutdown() async {
        stopping = true
        systemTimer?.invalidate(); usageTimer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        usageTask?.cancel()
        await usageTask?.value
    }
}
