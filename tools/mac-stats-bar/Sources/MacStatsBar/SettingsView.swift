import AppKit
import SwiftUI
import StatsCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("收纳托盘 · 预览") {
                Toggle("点击菜单栏图标展开托盘", isOn: $settings.trayEnabled)
                Toggle("菜单栏只显示小箭头", isOn: $settings.compactMenu)
                    .disabled(!settings.trayEnabled)
                Text("右键点击箭头，可直接打开系统与额度。托盘出现在菜单栏下方，避开刘海。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            group("菜单栏显示") {
                Toggle("CPU 使用率", isOn: $settings.showCPU)
                Toggle("内存使用率", isOn: $settings.showMemory)
                Toggle("Codex 剩余额度", isOn: $settings.showCodex)
                if let buckets = model.usage?.snapshot.buckets, buckets.count > 1 {
                    Picker("显示的额度", selection: $settings.selectedBucket) {
                        ForEach(buckets, id: \.id) { entry in
                            Text(entry.value.displayName(fallback: entry.id)).tag(entry.id)
                        }
                    }
                }
                Text("多个窗口同时存在时，菜单栏显示其中较低的余量。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            group("刷新频率") {
                Picker("系统状态", selection: $settings.systemInterval) {
                    Text("2 秒").tag(2.0)
                    Text("5 秒 · 推荐").tag(5.0)
                    Text("10 秒").tag(10.0)
                }
                Picker("Codex 额度", selection: $settings.codexInterval) {
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟 · 推荐").tag(300.0)
                    Text("10 分钟").tag(600.0)
                }
                Text("磁盘与电池每 30 秒更新。Mac 休眠时暂停刷新。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            group("Codex 连接") {
                Label(CodexExecutable.locate(customPath: settings.codexPath) == nil ? "未找到 Codex" : "已找到本机 Codex",
                      systemImage: CodexExecutable.locate(customPath: settings.codexPath) == nil ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text("使用 Codex 中已登录的 ChatGPT 账户。只读取额度，不保存登录凭据。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("选择 Codex…", action: chooseExecutable)
                    if !settings.codexPath.isEmpty {
                        Button("自动查找") { settings.codexPath = "" }
                    }
                    Spacer()
                    Button("立即同步") { model.refreshUsage() }.disabled(model.isRefreshing)
                }.controlSize(.small)
                if let path = CodexExecutable.locate(customPath: settings.codexPath)?.path {
                    Text(path).font(.system(size: 9)).foregroundStyle(.tertiary)
                        .textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                }
            }
            group("启动") {
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLaunchAtLogin))
                if let message = model.loginMessage {
                    Text(message).font(.system(size: 10)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Mac Stats Bar 0.2.0 Preview\n原生 Swift · 无第三方依赖 · 本地运行")
                .font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(4)
        }
        .font(.system(size: 12))
        .toggleStyle(.switch).controlSize(.small)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 程序"
        panel.message = "选择已安装的 codex 可执行文件。"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = CodexExecutable.locate()?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            settings.codexPath = url.path
        }
    }
}
