import AppKit
import ApplicationServices
import SwiftUI
import StatsCore

struct TrayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tray: TrayModel
    let openDashboard: (Bool) -> Void
    let organize: () -> Void
    let close: () -> Void

    private let accent = Color(red: 0.13, green: 0.61, blue: 0.48)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "tray.2.fill").foregroundStyle(accent)
                Text("收纳托盘").font(.system(size: 13, weight: .semibold))
                Text("PREVIEW").font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.primary.opacity(0.05), in: Capsule())
                Spacer()
                Button { tray.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(tray.isScanning || !tray.connected || !tray.hasAccess)
                    .help("刷新菜单栏应用").accessibilityLabel("刷新菜单栏应用")
                Button { openDashboard(true) } label: { Image(systemName: "gearshape") }
                    .help("偏好设置").accessibilityLabel("偏好设置")
                Button(action: close) { Image(systemName: "chevron.up") }
                    .help("收起托盘").accessibilityLabel("收起托盘")
            }
            .buttonStyle(.plain).font(.system(size: 12))
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 13)

            HStack(spacing: 10) {
                quickCard(symbol: "waveform.path", title: "系统状态", color: .blue) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        value(DisplayFormat.percent(model.system.cpuPercent), caption: "CPU")
                        value(DisplayFormat.percent(model.system.memory?.percent), caption: "内存")
                    }
                    Text("↓ \(DisplayFormat.rate(model.system.network?.download))  ↑ \(DisplayFormat.rate(model.system.network?.upload))")
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
                quickCard(symbol: "sparkles", title: "Codex 额度", color: accent) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        value(DisplayFormat.percent(model.selectedQuota?.remainingPercent(at: Date())), caption: "剩余")
                        Spacer(minLength: 0)
                        Text("重置卡 \(model.usage?.snapshot.rateLimitResetCredits?.count.map(String.init) ?? "—")")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(quotaDetail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 14)

            HStack(spacing: 7) {
                Text(tray.organizerEnabled && !tray.isArranging ? "已收纳的图标" : "菜单栏应用")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                if tray.connected && tray.hasAccess {
                    Text("\(tray.collectedExtras.count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
                    if tray.isScanning { ProgressView().controlSize(.mini).scaleEffect(0.65) }
                    Spacer()
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField("查找应用", text: $tray.search)
                        .font(.system(size: 10)).textFieldStyle(.plain).frame(width: 115)
                        .accessibilityLabel("查找菜单栏应用")
                } else { Spacer() }
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)

            if !tray.connected || !tray.hasAccess {
                permissionCard
            } else if tray.extras.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: tray.isScanning ? "ellipsis" : "tray")
                        .font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text(tray.isScanning ? "正在查找菜单栏应用…" : "暂未发现可接入的菜单栏项")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if !tray.isScanning {
                        Text("部分应用没有提供可访问的菜单项；可打开应用后刷新。")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(tray.visibleExtras) { extra in extraButton(extra) }
                    }.padding(.horizontal, 14).padding(.vertical, 4)
                }
                .frame(height: 98)
                .overlay {
                    if tray.visibleExtras.isEmpty {
                        Text(tray.search.isEmpty ? "收纳的应用目前未运行" : "没有匹配的应用")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            if let message = tray.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18).padding(.bottom, 6)
            }
            if tray.isArranging {
                HStack(spacing: 6) {
                    Image(systemName: "command").foregroundStyle(accent)
                    Text("按住 ⌘ 拖到分隔线左侧，再点「完成并收起」。")
                    Spacer()
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.bottom, 10)
            }
            Spacer(minLength: 8)
            Divider().opacity(0.45)
            HStack(spacing: 12) {
                Button { openDashboard(false) } label: {
                    Label("系统与额度", systemImage: "chart.bar.xaxis")
                }
                Spacer()
                if tray.connected && tray.hasAccess {
                    Menu {
                        if tray.organizerEnabled {
                            if !tray.isArranging {
                                Button(tray.originalsHidden ? "临时展开原图标" : "收起原图标") { tray.toggleOriginals() }
                            }
                            Button("停止收纳，恢复全部图标") { tray.stopOrganizing() }
                            Divider()
                        }
                        Button("断开菜单栏应用") { tray.disconnect() }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 22)
                        .accessibilityLabel("托盘连接选项")
                    if tray.isArranging {
                        Button("完成并收起") { tray.finishOrganizing() }
                            .buttonStyle(.borderedProminent).tint(accent).controlSize(.small)
                            .disabled(tray.isScanning)
                    } else if tray.organizerEnabled {
                        Label(tray.originalsHidden ? "原图标已隐藏" : "原图标暂时展开", systemImage: tray.originalsHidden ? "checkmark.circle.fill" : "eye")
                            .foregroundStyle(accent)
                        Button("重新整理", action: organize)
                    } else {
                        Button("整理菜单栏", action: organize)
                    }
                } else {
                    Text("只占一个菜单栏位置").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.17)))
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private var quotaDetail: String {
        guard let bucket = model.selectedQuota else { return model.connectionLabel }
        if model.isUsageStale { return "\(model.connectionLabel) · 点开查看详情" }
        guard let date = bucket.windows.compactMap({ $0.value.resetDate }).min() else { return model.updatedLabel }
        return "\(date.formatted(.dateTime.month().day().hour().minute())) 刷新"
    }

    private func value(_ text: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(caption).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func quickCard<Content: View>(symbol: String, title: String, color: Color,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button { openDashboard(false) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(color)
                    Text(title).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                }.font(.system(size: 10, weight: .medium))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)")
    }

    private var permissionCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text("把菜单栏应用放进这里").font(.system(size: 12, weight: .medium))
                Text("允许辅助功能后，可在这里查找并打开其他应用的菜单。\n图标使用应用图标，部分应用可能不支持。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                Button(tray.connected ? "前往辅助功能设置…" : "连接菜单栏应用…") { tray.connect() }
                    .controlSize(.small).tint(accent)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
    }

    private func extraButton(_ extra: MenuExtra) -> some View {
        Button {
            let action = extra.actions.contains(kAXPressAction) ? kAXPressAction : kAXShowMenuAction
            tray.onOpenExtra?(extra, action)
        } label: {
            VStack(spacing: 7) {
                Group {
                    if let icon = extra.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "menubar.rectangle").resizable().scaledToFit() }
                }.frame(width: 27, height: 27)
                    .frame(width: 48, height: 46)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                Text(extra.label).font(.system(size: 9)).lineLimit(2)
                    .multilineTextAlignment(.center).frame(width: 67, height: 25, alignment: .top)
            }.frame(width: 72)
        }
        .buttonStyle(.plain).help("\(extra.appName) · \(extra.label)")
        .accessibilityLabel("打开\(extra.label)菜单")
        .contextMenu {
            Button("打开菜单") { tray.onOpenExtra?(extra, kAXPressAction) }
                .disabled(!extra.actions.contains(kAXPressAction))
            Button("打开右键菜单") { tray.onOpenExtra?(extra, kAXShowMenuAction) }
                .disabled(!extra.actions.contains(kAXShowMenuAction))
            Divider()
            Button("在托盘中向前移动") { tray.move(extra, by: -1) }
            Button("在托盘中向后移动") { tray.move(extra, by: 1) }
        }
    }
}
