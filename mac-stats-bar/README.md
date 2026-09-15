# Mac Stats Bar · Screwdriver

一个原生、轻量的 macOS 菜单栏工具：系统状态与 Codex 订阅额度，一眼可见。

[← 返回螺丝刀工具箱](../README.md) · [图文入口](../mac-stats-bar.html)

借鉴 [iStat Menus 的合并菜单栏交互](https://bjango.com/mac/istatmenus/)，用 Swift、AppKit 和 SwiftUI 实现。无需第三方包、浏览器运行时或管理员辅助服务。

## 使用

当前收录的是包含「完成并收起」修正的托盘预览版（源提交 `073fd66`）。默认生成 **Mac Stats Bar Preview.app**，延续原有应用标识 `local.macstatsbar.preview`。迁入说明见 [来源与验证记录](docs/integration.md)。

需要 macOS 13 或更新版本。构建需要 Apple Command Line Tools（本机以 Swift 6.0.3 验证），Codex 额度需要本机安装 Codex 并登录 ChatGPT 账户。

```sh
cd mac-stats-bar
./scripts/build.sh preview
open "dist/Mac Stats Bar Preview.app"
```

以上从螺丝刀仓库根目录开始。也可以直接从根目录调用 `./mac-stats-bar/scripts/build.sh`；脚本会自行定位工具目录。后面的命令均在 `mac-stats-bar/` 中运行。

<img src="../screenshots/mac-stats-bar.jpg" alt="Mac Stats Bar 系统状态与 Codex 额度面板，全部为虚构演示数据" width="390" />

截图使用虚构演示数据，不展示个人账户的真实额度。

点击菜单栏的 **小箭头** 展开刘海下方的收纳托盘；右键点击箭头直接打开系统与额度详情。托盘中的状态卡片也可进入详情。应用不占 Dock 位置。

默认菜单栏只保留小箭头。关闭设置中的「菜单栏只显示小箭头」，可恢复 `CPU 12% · C 76%` 读数。`C` 是选中额度组的剩余百分比；同时有多个窗口时显示其中最小值。

## 收纳托盘预览

- 托盘显示真实系统状态、Codex 余量、恢复时间与重置卡数量。
- 点击「连接菜单栏应用」，在 macOS 辅助功能设置中允许预览版访问，然后重新打开托盘。可查找并打开其他应用提供的菜单栏项。
- 图标使用应用图标；点击调用该应用自己的菜单。右键菜单可调整托盘内顺序，并在应用支持时打开它的右键菜单。
- 「整理菜单栏」会添加一条分隔线。按住 ⌘ 将希望隐藏的图标拖到线左侧，再点击「完成并收起」。完成后主菜单栏隐藏这批图标，托盘只显示这些收纳项。箭头应保持在线右侧。
- 「重新整理」用于调整收纳范围。「停止收纳，恢复全部图标」放在右下角的更多菜单中。
- 操作外部菜单前会临时展开原图标；下次关闭托盘时再收起。停止收纳、关闭托盘功能或退出应用会恢复显示。
- 托盘只在打开或手动刷新时扫描菜单栏项。无需录屏权限，不截取桌面。

这是基于公开辅助功能接口的首版，并非所有应用都提供可操作菜单。原菜单仍由原应用定位；图标本身的精确外观复制、原菜单重新定位到第二排、原生图标拖拽排序尚未实现。整理状态在退出、休眠或屏幕布局变化后结束，需要重新开启。详见 [预览验证与边界](docs/history/tray-verification.md)。

### 构建版本与辅助功能授权

- 无参数构建与 `preview` 均生成 `Mac Stats Bar Preview.app`。保留 `stable` 参数供原有应用标识使用：生成 `Mac Stats Bar.app`（`local.macstatsbar.app`）。**两种参数编译同一份当前源码**，不是切回旧版；日常使用选默认预览包即可。
- 默认使用临时签名。更新或更换应用位置后，macOS 可能仍显示旧条目已授权，而新构建无法访问。退出应用，在「系统设置 → 隐私与安全性 → 辅助功能」移除旧条目，再添加当前构建并重新打开。
- 如果本机已有用于该应用的固定代码签名身份，可在构建时传入 `MAC_STATS_CODESIGN_IDENTITY`；脚本会使用该身份并验证签名。证书的创建与安装由开发者自行管理。

## 首版功能

| 模块 | 内容 | 默认刷新 |
| --- | --- | --- |
| CPU | 整机使用率、短期趋势、核心数、系统散热状态 | 5 秒 |
| 内存 | 已用 / 总量、趋势、内存压力、交换空间 | 5 秒 |
| 网络 | 物理接口下载、上传速率 | 5 秒 |
| 磁盘 | 主目录所在卷可用 / 总容量 | 30 秒 |
| 电池 | 电量和供电状态，有内置电池时显示 | 30 秒 |
| Codex | 各额度组余量、实际窗口长度、恢复日期与倒计时 | 5 分钟 |
| 重置卡 | 服务返回的可用张数、已知最近到期时间 | 随额度同步 |

支持手动同步、自动刷新暂停、休眠暂停与唤醒恢复、浅色 / 深色随系统、可选登录启动。

重置卡当前提供**展示**；可通过「用量详情」前往 Codex 管理。应用不会自动消费重置卡。

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

## 轻量化设计

- CPU、内存通过 Mach / sysctl 读取；网络用 64 位接口计数器，不反复启动 `top` 等进程。
- 网络只合计 `en*` 物理接口，排除回环、VPN 与桥接接口的重复计数；接口重连重新建立差分基线。
- 内存已用近似为 `(internal - purgeable + wired + compressor) × pageSize`，含物理压缩内存，不等同于所有进程 RSS 之和。
- 磁盘可用容量采用系统的「重要用途可用容量」，包括可回收空间。
- 仅保留最近 60 个有效 CPU / 内存采样点；关闭面板时释放视图。定时器允许系统合并唤醒。
- Codex 查询在后台工作队列执行，有总超时和取消；退出、暂停或休眠会取消查询并清理本次子进程。

当前范围是常用状态指标。GPU、温度传感器、风扇控制和逐进程统计尚未实现。资源占用需要以实际测量为准，不能仅由原生技术选型推断。

## 验证与诊断

当前测试集包含 23 项检查；本次在螺丝刀目录重新执行的结果见 [迁入验证](docs/integration.md)。[原有初版验证](docs/history/baseline-verification.md) 与 [托盘验证](docs/history/tray-verification.md) 及其资源测量保留在 `docs/history/`；公开副本已移除账户读数，其中的内存与 CPU 数值属于原仓库当时的测量，不作为迁入后的新测量。

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

本机构建使用临时签名，适合本地运行。对外分发前还需要 Developer ID 签名、公证以及更多机型与系统版本测试。

## 源码

```text
Sources/StatsCore/       额度数据模型、只读通信、原生系统采样
Sources/MacStatsBar/     菜单栏入口、界面、设置、刷新调度
Tests/StatsCoreTests/    数据语义与通信 / 采样测试
Resources/Info.plist     无 Dock 菜单栏应用声明
scripts/                本地构建和测试
docs/history/           迁入前的验证记录与原始测量
```

本工具随 Screwdriver 使用仓库根目录的 [MIT License](../LICENSE)。
