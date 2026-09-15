import AppKit
import SwiftUI
import StatsCore

private enum Palette {
    static let mint = Color(red: 0.10, green: 0.64, blue: 0.48)
    static let blue = Color(red: 0.29, green: 0.53, blue: 0.89)
    static let violet = Color(red: 0.55, green: 0.43, blue: 0.83)
    static let orange = Color(red: 0.91, green: 0.53, blue: 0.24)
    static let card = Color.primary.opacity(0.035)
    static func quota(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        return percent <= 10 ? .red : (percent <= 25 ? orange : mint)
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @State private var showingSettings = false
    @State private var showingOtherQuotas = false

    init(model: AppModel, settings: AppSettings, showingSettings: Bool = false) {
        self.model = model
        self.settings = settings
        self._showingSettings = State(initialValue: showingSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            ScrollView {
                VStack(spacing: 18) {
                    if showingSettings {
                        SettingsView(model: model, settings: settings)
                    } else {
                        systemSection
                        codexSection
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            Divider().opacity(0.45)
            footer
        }
        .frame(width: 388, height: 660)
        .background(.regularMaterial)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: showingSettings ? "slider.horizontal.3" : "waveform.path")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.mint)
                .frame(width: 34, height: 34)
                .background(Palette.mint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(showingSettings ? "偏好设置" : "Mac Stats Bar").font(.system(size: 15, weight: .semibold))
                Text(showingSettings ? "按你的节奏运行" : "你的 Mac，一眼掌握")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !showingSettings {
                Text(model.isPaused ? "已暂停" : "实时")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(model.isPaused ? .secondary : Palette.mint)
            }
            Button { showingSettings.toggle() } label: {
                Image(systemName: showingSettings ? "arrow.left" : "gearshape")
                    .font(.system(size: 13)).frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "返回概览" : "偏好设置")
            .accessibilityLabel(showingSettings ? "返回概览" : "偏好设置")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var systemSection: some View {
        VStack(spacing: 12) {
            sectionHeading("系统状态", detail: model.system.thermalLabel)
            HStack(spacing: 10) {
                metricCard(title: "CPU", value: DisplayFormat.percent(model.system.cpuPercent),
                           detail: "\(model.system.coreCount) 核处理器", history: model.cpuHistory, color: Palette.blue)
                metricCard(title: "内存", value: DisplayFormat.percent(model.system.memory?.percent),
                           detail: model.system.memory.map { "\(DisplayFormat.bytes($0.used)) / \(DisplayFormat.bytes($0.total))" } ?? "等待采样",
                           history: model.memoryHistory, color: Palette.violet)
            }
            HStack(spacing: 12) {
                Image(systemName: "network").foregroundStyle(.secondary).frame(width: 18)
                networkValue(symbol: "arrow.down", value: model.system.network?.download, color: Palette.blue)
                Spacer(minLength: 0)
                networkValue(symbol: "arrow.up", value: model.system.network?.upload, color: Palette.violet)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
            .help("Wi-Fi 与以太网等物理接口合计，不重复累计 VPN 和虚拟接口。")
            VStack(spacing: 11) {
                HStack(spacing: 9) {
                    Image(systemName: "internaldrive").foregroundStyle(.secondary).frame(width: 18)
                    Text("磁盘可用").font(.system(size: 11))
                    Spacer()
                    Text(model.system.disk.map { "\(DisplayFormat.bytes($0.available)) / \(DisplayFormat.bytes($0.total))" } ?? "未知")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                }
                .help("主目录所在卷的可用容量，包含系统可回收空间。")
                if let battery = model.system.battery {
                    HStack(spacing: 9) {
                        Image(systemName: battery.isPluggedIn ? "battery.100percent.bolt" : "battery.75percent")
                            .foregroundStyle(battery.percent <= 20 ? Palette.orange : Palette.mint).frame(width: 18)
                        Text(battery.label).font(.system(size: 11))
                        Spacer()
                        Text(DisplayFormat.percent(battery.percent)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                }
                HStack(spacing: 9) {
                    Circle().fill(memoryPressureColor).frame(width: 6, height: 6).frame(width: 18)
                    Text(model.system.memory?.pressureLabel ?? "内存压力未知")
                    Spacer()
                    if let swap = model.system.memory?.swapUsed { Text("交换 \(DisplayFormat.bytes(swap))") }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
    }

    private var memoryPressureColor: Color {
        switch model.system.memory?.pressure {
        case 1: return Palette.mint
        case 2: return Palette.orange
        case 4: return .red
        default: return .secondary
        }
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CODEX").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                if let plan = model.selectedQuota?.planLabel {
                    Text(plan).font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Palette.card, in: Capsule())
                }
                Spacer()
                Circle().fill(model.isUsageStale ? Palette.orange : Palette.mint).frame(width: 5, height: 5)
                Text(model.connectionLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                Button { model.refreshUsage() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)).frame(width: 24, height: 22)
                }
                .buttonStyle(.plain).disabled(model.isRefreshing)
                .help("立即同步 Codex 额度").accessibilityLabel("立即同步 Codex 额度")
            }
            if let error = model.usageError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(Palette.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let bucket = model.selectedQuota, let id = model.selectedBucketID {
                quotaCard(bucket: bucket, id: id)
            } else if model.isRefreshing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Codex 额度…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("连接你的 Codex").font(.system(size: 13, weight: .medium))
                    Text("使用本机已登录的 ChatGPT 账户，展示订阅余量与恢复时间。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("连接设置") { showingSettings = true }.controlSize(.small).padding(.top, 3)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            }
            resetCard
            if let other = model.usage?.snapshot.buckets.filter({ $0.id != model.selectedBucketID }), !other.isEmpty {
                Button { showingOtherQuotas.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showingOtherQuotas ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("其他额度 · \(other.count)").font(.system(size: 11))
                        Spacer()
                    }
                    .foregroundStyle(.secondary).padding(.vertical, 3).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingOtherQuotas ? "收起其他额度" : "展开其他额度")
                if showingOtherQuotas {
                    VStack(spacing: 9) {
                        ForEach(other, id: \.id) { entry in quotaCard(bucket: entry.value, id: entry.id) }
                    }
                }
            }
            HStack {
                Text(model.updatedLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(model.usage.map { "上次成功同步：\(absoluteDate($0.fetchedAt))" } ?? "尚未成功读取额度")
                Spacer()
                Link(destination: URL(string: "https://chatgpt.com/codex/settings/usage")!) {
                    Label("用量详情", systemImage: "arrow.up.right").font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func quotaCard(bucket: QuotaBucket, id: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if id != "codex" { Text(bucket.displayName(fallback: id)).font(.system(size: 11, weight: .semibold)) }
            if bucket.windows.isEmpty {
                Text("服务未提供额度窗口").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(bucket.windows, id: \.id) { entry in
                let window = entry.value
                let expired = window.isAwaitingReset(at: Date())
                let remaining = expired ? nil : window.remainingPercent
                let color = Palette.quota(remaining)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(window.title).font(.system(size: 11, weight: .medium))
                            Text(DisplayFormat.countdown(to: window.resetDate, now: Date()))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(expired ? "待同步" : DisplayFormat.percent(remaining))
                            .font(.system(size: expired ? 18 : 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(color).monospacedDigit()
                        if !expired { Text("剩余").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                    Meter(value: remaining, color: color)
                    if let reset = window.resetDate {
                        Text("恢复于 \(absoluteDate(reset))")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            if model.isUsageStale { Text("上次成功读数 · 可能已过期").font(.system(size: 10)).foregroundStyle(Palette.orange) }
            if bucket.spendControlReached == true {
                Label("已达到支出限制", systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(Palette.orange)
            }
        }
        .padding(13)
        .background(Palette.mint.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.mint.opacity(0.1), lineWidth: 1))
    }

    private var resetCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket").font(.system(size: 19)).foregroundStyle(Palette.violet)
                .frame(width: 32, height: 32)
                .background(Palette.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("重置卡").font(.system(size: 11, weight: .medium))
                Text(resetDetail).font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(model.usage?.snapshot.rateLimitResetCredits?.count.map(String.init) ?? "—")
                .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("张").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
        .help("显示服务返回的可用重置卡数量。可在 Codex 中使用重置卡。")
    }

    private var resetDetail: String {
        guard let summary = model.usage?.snapshot.rateLimitResetCredits, let count = summary.count else { return "服务暂未提供数量" }
        if count == 0 { return "暂无可用重置卡" }
        if let expiry = summary.nextKnownExpiry {
            if expiry <= Date() { return "已知卡片已到期 · 等待同步" }
            return "已知最近到期：\(absoluteDate(expiry))"
        }
        if summary.credits == nil { return "可在 Codex 中使用 · 有效期未知" }
        return "可在 Codex 中使用"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.togglePaused() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill").font(.system(size: 10)).frame(width: 20, height: 22)
            }
            .buttonStyle(.plain).help(model.isPaused ? "恢复自动刷新" : "暂停自动刷新")
            .accessibilityLabel(model.isPaused ? "恢复自动刷新" : "暂停自动刷新")
            Text(model.isPaused ? "自动刷新已暂停" : "系统 \(Int(settings.systemInterval)) 秒 · 额度 \(Int(settings.codexInterval / 60)) 分钟")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11)).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).help("退出 Mac Stats Bar").accessibilityLabel("退出 Mac Stats Bar")
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func metricCard(title: String, value: String, detail: String, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 5) {
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                Sparkline(values: history, color: color).frame(width: 52, height: 25).padding(.bottom, 4)
            }
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func networkValue(symbol: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(DisplayFormat.rate(value)).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .accessibilityLabel("\(symbol == "arrow.down" ? "下载" : "上传") \(DisplayFormat.rate(value))")
    }

    private func absoluteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

private struct Meter: View {
    let value: Double?
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                if let value { Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, value / 100))) }
            }
        }.frame(height: 5).accessibilityHidden(true)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            if values.count > 1 {
                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(x: CGFloat(index) / CGFloat(values.count - 1) * geometry.size.width,
                                            y: geometry.size.height * (1 - min(100, max(0, value)) / 100))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}
