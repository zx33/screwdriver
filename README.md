# 🪛 Screwdriver

一个小而灵巧的本地工具箱，处理文档对比、格式转换和 Mac 菜单栏里的小麻烦。

**[打开工具箱首页](index.html)** · 下载或克隆仓库后，可直接用浏览器打开，无需安装前端依赖。

## 工具目录

| 工具 | 用途 | 运行环境 | 入口与说明 |
| --- | --- | --- | --- |
| **Markdown Review** | 对比两份 Markdown，查看行内修订或源码并排差异 | 浏览器 | [打开工具](tools/markdown-review/index.html) · [使用说明](tools/markdown-review/README.md) |
| **Markdown → Word** | 将 Markdown 转成可继续编辑的 `.docx` 文档 | 浏览器 | [打开工具](tools/md-to-docx/index.html) · [使用说明](tools/md-to-docx/README.md) |
| **Mac Stats Bar** | 在 macOS 菜单栏查看系统状态、Codex 额度并收纳图标 | macOS 13+ | [图文介绍](tools/mac-stats-bar/index.html) · [构建与使用](tools/mac-stats-bar/README.md) |

## 开始使用

### 文档工具

打开根目录的 [`index.html`](index.html)，选择工具即可。也可以通过上表直接打开某个工具的页面。

两个文档工具均在当前浏览器中读取和处理内容，不上传文档。支持直接打开本地文件，也支持通过静态文件服务器访问整个仓库。

### Mac Stats Bar

需要 macOS 13+ 和 Apple Command Line Tools。在仓库根目录运行：

```sh
./tools/mac-stats-bar/scripts/build.sh
open "tools/mac-stats-bar/dist/Mac Stats Bar Preview.app"
```

Codex 额度需要本机安装 Codex 并登录，查询经本机 Codex 连接 OpenAI。菜单栏收纳为预览功能，需要辅助功能授权。详细操作见 [Mac Stats Bar 使用说明](tools/mac-stats-bar/README.md)。

## 仓库结构

```text
.
├── README.md                 工具目录、快速开始与维护入口
├── index.html                浏览器工具箱首页
├── assets/
│   ├── base.css              各页面共用的基础样式
│   └── toolbox.css           工具箱首页样式
├── tools/
│   ├── markdown-review/      Markdown 对比：页面、脚本、样式与截图
│   ├── md-to-docx/           Markdown 转 Word：页面、转换引擎与测试
│   └── mac-stats-bar/        原生应用：页面、Swift 源码、构建脚本与文档
└── LICENSE
```

每个工具都有自己的 `README.md`、`index.html`、`styles.css` 和 `screenshot.jpg`。工具专用的源码、测试与文档放在各自目录；多个页面实际共用的资源放在 `assets/`。

## 开发与维护

网页工具直接修改对应目录中的 HTML、CSS 和 JavaScript，刷新页面即可。Mac Stats Bar 的构建、数据来源和诊断方式见 [开发说明](tools/mac-stats-bar/docs/development.md)。

在仓库根目录运行现有测试：

```sh
node --test tools/md-to-docx/tests/docx-engine.test.js
./tools/mac-stats-bar/scripts/test.sh
```

添加工具时，在 `tools/<工具名>/` 中放入实现和使用说明，再更新本页的工具目录与首页入口。功能细节和截图放在工具自己的 README；历史记录放在该工具的 `docs/history/`。

## License

[MIT License](LICENSE)
