# Mac Stats Bar 开发说明

[← 返回使用说明](../README.md)

用 Swift、AppKit 和 SwiftUI 实现，无第三方包。菜单栏交互参考 [iStat Menus](https://bjango.com/mac/istatmenus/)。

先从仓库根目录进入工具目录并构建，后续命令均在此目录中运行：

```sh
cd tools/mac-stats-bar
./scripts/build.sh
```

## 构建版本与签名

- 无参数构建与 `preview` 均生成 `Mac Stats Bar Preview.app`。保留 `stable` 参数供原有应用标识使用：生成 `Mac Stats Bar.app`（`local.macstatsbar.app`）。**两种参数编译同一份当前源码**，不是切回旧版；日常使用选默认预览包即可。
- 默认使用临时签名，应用标识为 `local.macstatsbar.preview`。更新后的授权问题见 [辅助功能授权](../README.md#辅助功能授权)。
- 如果本机已有用于该应用的固定代码签名身份，可在构建时传入 `MAC_STATS_CODESIGN_IDENTITY`；脚本会使用该身份并验证签名。证书的创建与安装由开发者自行管理。

对外分发需要 Developer ID 签名与公证。

## 源码

```text
Sources/StatsCore/       额度数据模型、只读通信、原生系统采样
Sources/MacStatsBar/     菜单栏入口、界面、设置、刷新调度
Tests/StatsCoreTests/    数据语义与通信 / 采样测试
Resources/Info.plist     无 Dock 菜单栏应用声明
scripts/                本地构建和测试
docs/history/           迁入、验证与资源测量的历史记录
```

## Codex 数据来源

通过本机 `codex app-server --listen stdio://`，按 [OpenAI App Server 文档](https://learn.chatgpt.com/docs/app-server) 完成 `initialize` → `initialized` → `account/rateLimits/read`。每次查询完成即关闭连接和本次创建的子进程，不创建任务、不调用模型。

- 复用 Codex 的登录状态；应用不读取、复制或保存认证文件。
- 额度查询由 Codex 连接 OpenAI；系统状态只在本机采集。
- 仅在内存中保留最近成功读数，不写额度历史、账户标识或认证信息。
- 优先按 `rateLimitsByLimitId` 分组，兼容旧版 `rateLimits`。
- 余量为 `clamp(100 - usedPercent, 0, 100)`。窗口标签来自 `windowDurationMins`，不假定主窗口一定是 5 小时。
- `resetsAt` 是 Unix 秒，转换为本机时区。到时仅显示待同步，不能推断已恢复为 100%。
- 未提供的数据显示未知；同步失败保留旧读数并标记。菜单栏的 `~` 表示缓存可能过期。
- 重置卡数量采用 `rateLimitResetCredits.availableCount`。明细可能被截断，因此「已知最近到期」不保证覆盖全部卡片。余额 credits 与重置卡分开解释。
- 默认每 5 分钟读取；在已知的额度恢复或卡片到期时间附近重新读取。错误后逐步退避，最多 15 分钟。

自动查找常见 Codex 安装路径。若使用自定义安装，可在设置中选择可执行文件。独立应用的账户以它找到的本机 Codex 登录状态为准。

## 采样与刷新实现

- CPU、内存通过 Mach / sysctl 读取；网络用 64 位接口计数器，不反复启动 `top` 等进程。
- 网络只合计 `en*` 物理接口，排除回环、VPN 与桥接接口的重复计数；接口重连重新建立差分基线。
- 内存已用近似为 `(internal - purgeable + wired + compressor) × pageSize`，含物理压缩内存，不等同于所有进程 RSS 之和。
- 磁盘可用容量采用系统的「重要用途可用容量」，包括可回收空间。
- 仅保留最近 60 个有效 CPU / 内存采样点；关闭面板时释放视图。定时器允许系统合并唤醒。
- Codex 查询在后台工作队列执行，有总超时和取消；退出、暂停或休眠会取消查询并清理本次子进程。

当前范围是常用状态指标。GPU、温度传感器、风扇控制和逐进程统计尚未实现。资源占用需要以实际测量为准，不能仅由原生技术选型推断。

## 测试与诊断

运行现有检查，或对构建后的应用执行一次诊断：

```sh
./scripts/test.sh
"dist/Mac Stats Bar Preview.app/Contents/MacOS/MacStatsBar" --diagnose
```

诊断命令执行真实系统采样和一次只读额度请求，输出不含账户 ID、重置卡 ID 和认证信息。额度读取失败时退出码为 1。

测试覆盖窗口语义、空值、额度分组、重置卡数量、时间过期、CPU 计数回绕、网络重连、真实管道的握手/超时/取消，以及刘海安全区域、多屏负坐标、侧边 Dock、自动隐藏菜单栏与托盘顺序恢复。

检查程序不依赖 XCTest 或完整 Xcode。可选资源测量工具为 `scripts/measure-resources.py`，需要 Python 3；这不属于应用运行依赖。

```sh
python3 scripts/measure-resources.py --diagnostic --output dist/diagnostic-measurement.json
```

测量脚本也默认选择预览包；测量 `stable` 包时加 `--flavor stable`。测量常驻应用时，以 `--pid <进程号>` 替代 `--diagnostic`，关闭面板后执行。结果保存在忽略的 `dist/`，不会混入历史记录。

构建产物在 `dist/`，缓存都在 `.build/`。`scripts/environment.sh` 会为某些升级后混有旧接口文件的 Apple 工具链创建项目内兼容副本，不修改系统工具链。

## 历史记录

[迁入记录](history/integration.md)、[初版验证](history/baseline-verification.md)、[托盘验证](history/tray-verification.md)与[发布隐私记录](history/privacy-review.md)均保留在 `history/`。记录中的测试结果和资源测量对应各自标注的日期。

迁入源项目为 `mac_stats_bar` 的 `feature/expandable-tray` 分支，源提交为 `073fd66`；后续维护在当前工具目录继续。
