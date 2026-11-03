# mdcat

在 Bash 中阅读排版后的 Markdown，也可以从命令行打开带图片和公式的浏览器预览。

支持 macOS 和 Linux。独立可执行文件包含渲染资源，使用时不需要 Node.js、Deno 或联网。

## 独立可执行文件

按系统和 CPU 选择 `dist/` 中对应的文件：

| 平台 | 文件 |
| --- | --- |
| Apple Silicon Mac | `mdcat-macos-arm64` |
| Intel Mac | `mdcat-macos-x64` |
| Linux x86-64 | `mdcat-linux-x64` |
| Linux ARM64 | `mdcat-linux-arm64` |

每个文件约 7 MB。Linux 版本为静态链接文件。

例如，在仓库根目录使用 Apple Silicon 版：

```bash
./tools/mdcat/dist/mdcat-macos-arm64 README.md
./tools/mdcat/dist/mdcat-macos-arm64 --browser README.md
```

单个文件可以复制到其他位置，或改名为 `mdcat` 后放进 `PATH` 中。`dist/` 是本地构建产物，不随源码仓库提交；如果目录不存在，请按文末说明构建。

## 仓库内的便捷入口

`tools/mdcat/mdcat` 会选择当前系统对应的独立文件。在仓库根目录运行：

```bash
./tools/mdcat/mdcat README.md
./tools/mdcat/mdcat /path/to/document.md
cat README.md | ./tools/mdcat/mdcat
```

如果想在任意目录直接使用 `mdcat`，可以在 Bash 配置文件（例如 `~/.bashrc`，macOS 上按实际加载的配置文件选择）中添加一条别名，将路径换成这个仓库的实际路径：

```bash
alias mdcat='/path/to/markdown_diff_tools/tools/mdcat/mdcat'
```

重新打开终端或重新加载配置后，即可使用：

```bash
mdcat notes.md
mdcat --browser notes.md
```

也可以把 `tools/mdcat/mdcat` 的符号链接放进已经加入 `PATH` 的目录。

## 终端与浏览器

- 终端支持标题、强调、链接、列表、任务列表、引用、代码块和表格。交互式终端自动启用颜色，重定向或管道输出默认不带颜色。
- iTerm2、WezTerm 可直接显示 Markdown 引用的本地 PNG、JPEG 和 GIF；Kitty 可直接显示本地 PNG。本地图片大小限 20 MiB。其他终端、远程图片和无法显示的图片会显示图片描述与路径。终端图片显示需要直接输出到终端，不通过 `less` 或管道。
- 终端中公式以高亮的 LaTeX 原文显示，支持 `$...$`、`$$...$$` 和 `\(...\)`、`\[...\]`。浏览器预览使用 KaTeX 排版公式，同时显示本地和网络图片；相对路径以 Markdown 文件所在目录为基准。管道输入以当前目录为基准。
- macOS 浏览器预览使用 `open`，Linux 使用 `xdg-open`。预览 HTML 保存在系统临时目录中；文档中的网络图片由浏览器加载。

```bash
mdcat --browser notes.md                 # 浏览器预览
mdcat --color notes.md | less -R         # 分页阅读并保留颜色
mdcat --no-color notes.md               # 不使用颜色
mdcat --no-images notes.md              # 终端中只显示图片描述与路径
mdcat --help
```

## 构建与开发

构建独立可执行文件需要 Go 1.27.3 或更新版本。首次构建时需要下载 Go 模块；之后可以使用缓存构建。

```bash
./tools/mdcat/scripts/build.sh               # 构建当前平台
./tools/mdcat/scripts/build.sh linux-x64     # 指定目标平台
./tools/mdcat/scripts/build.sh linux-arm64
./tools/mdcat/scripts/build.sh macos-x64
./tools/mdcat/scripts/build.sh macos-arm64
```

测试源码：

```bash
(cd tools/mdcat && go test ./...)
```

Markdown 解析使用 Goldmark 1.8.7，公式排版使用 KaTeX 0.18.1；KaTeX 许可文件见 `assets/katex/LICENSE`。
