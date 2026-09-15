# 迁入 Screwdriver

日期：2026-09-15。

## 来源

- 原项目：`mac_stats_bar`，分支 `feature/expandable-tray`。
- 源提交：`073fd66a07d232c5ae03313154d2601a5f6e9e27`（Fix finishing menu bar collection to hide selected icons）。
- 从干净工作区复制受版本控制的文件，整合到 `mac-stats-bar/`；不嵌套原仓库的 Git 元数据。
- `Sources/`、`Tests/`、`Package.swift` 和 `Resources/Info.plist` 保留源版本；导入前后核对文件内容。运行逻辑继续包含用户已测试的「完成并收起」修正。

## 整理内容

- 将原项目的忽略规则并入工具箱，排除 Swift 缓存、构建产物和本地测量输出。
- 更新工具箱 README、工具切换入口与独立使用页；添加原生面板截图，发布前改用明确标注的虚构演示数据。
- 清理依赖独立仓库分支的说明，将旧验证与原始测量移至 `docs/history/`，并省略历史记录中的个人应用名单。
- 构建参数先校验再准备环境；支持指定已有代码签名身份，构建结束验证签名。默认包名、应用标识与临时签名方式保持一致。
- 资源测量默认目标改为预览包，与构建默认值一致；用 `--flavor stable` 指定另一个应用包，拒绝无效测量时长。

## 验证

环境：macOS 15.1.1，Apple Silicon；Apple Swift 6.0.3。

| 检查 | 本次结果 |
| --- | --- |
| 来源完整性 | 应用源码、测试、包清单与应用配置共 18 个文件的 SHA-256 与源版本一致；原项目全部受版本控制的文件未改变 |
| 原生检查 | 从螺丝刀根目录执行 `./mac-stats-bar/scripts/test.sh`，23 通过、0 失败 |
| Release 构建 | 从螺丝刀根目录执行默认构建，成功生成 `mac-stats-bar/dist/Mac Stats Bar Preview.app` |
| 应用包 | `Info.plist` 格式检查、`codesign --verify --strict` 均通过；默认临时签名已验证 |
| 新包真实诊断 | 测量脚本默认选择预览包，系统采样成功，Codex 查询成功，返回 2 个额度组，退出码 0 |
| 脚本参数 | 非法构建参数、非正数与非有限测量时长均在执行前拒绝 |
| Word 转换回归 | `node --test tests/docx-engine.test.js`，5 通过、0 失败；原有 JavaScript 语法检查通过 |
| 页面 | 浏览器实测 Mac Stats Bar → Markdown 对比 → MD 转 Word → Mac Stats Bar；原有示例显示正常，收纳说明可展开，截图成功加载，控制台无错误，当前视口无横向溢出 |
| 仓库整理 | 本地文档与页面链接有效；构建缓存、应用包和本次诊断输出被忽略；变更未引入凭据、个人路径或嵌套 Git 仓库 |

本次诊断原始输出保存在本机忽略的 `mac-stats-bar/dist/integration-diagnostic.json`，可用下列命令重新生成：

```sh
python3 mac-stats-bar/scripts/measure-resources.py --diagnostic --output mac-stats-bar/dist/integration-diagnostic.json
```

这是一次命令行系统采样和额度查询，不是 GUI 常驻资源基准。迁入没有重做辅助功能授权、收纳操作的 GUI 回归或长期能耗测量；这些边界与历史验证分开记录。

## 发布隐私检查

公开源码和 Git 提交元数据完成敏感信息检查；截图改用虚构演示数据，历史诊断副本移除个人账户与系统诊断明细。原始记录保留在本地源项目。检查范围与结果见 [privacy-review.md](privacy-review.md)。

## 范围

- 公开截图使用相同的原生视图，在独立的临时程序中载入虚构系统与额度数据后渲染。截图内标注「演示」，未连接账户；它与上面的真实诊断验证分别记录。
- 新目录的构建与诊断单独验证；原有正在使用的托盘和收纳布局继续保留。
- 历史性能记录不是本次重新测量。长时间能耗、多显示器与休眠的实际硬件测试、正式签名和公证仍遵循历史记录中的未验证边界。
