# 🪛 Screwdriver

一个小而灵巧的本地工具箱：专门处理那些“不值得开大炮，但又确实有点烦”的小问题。

每把工具都尽量做到：打开就能用、数据留在本地、界面不端着。螺丝有点松？拧一下就好。😈

## 工具箱

### Markdown Review

双 Markdown 文档对比工具，提供类似 Overleaf Review 的行内修订视图，也可以切换到源码并排模式。

![Markdown Review 截图](screenshots/markdown-review.jpg)

它会把差异拆成容易读的“小动作”：

- 双文档输入：左边是修改前，右边是修改后
- 修订视图：新增内容带下划线，删除内容带删除线
- 源码并排：需要逐行核对时，左右对照更稳
- Word / Char 粒度：英文按词看，中文也能按字符看
- 修改统计：新增、删除、修改行和连续修改区域一眼可见
- 上一个 / 下一个修改：长文档里不用手动考古

> 适合：论文、README、会议纪要、产品文案，以及所有“我明明只改了几处，怎么变成这样”的 Markdown 文件。

## 使用

直接打开 [`index.html`](index.html) 即可使用；也可以在当前目录启动任意静态文件服务器。

所有对比都在浏览器本地完成，不会把文档上传到服务器。这个工具箱目前是纯前端、零依赖，拿来即用。

## 设计口味

- local-first：先照顾手里的文件，再考虑联网服务
- small tools：一把工具解决一个具体的小麻烦
- readable diff：差异是给人看的，不是给日志看的
- friendly mischief：认真做事，偶尔眨一下眼睛 😈

## 开发

仓库当前没有构建步骤。修改 `index.html`、`styles.css`、`app.js` 或 `diff-engine.js` 后，刷新浏览器即可检查效果。

```text
screwdriver/
├── index.html
├── styles.css
├── app.js
├── diff-engine.js
└── screenshots/
    └── markdown-review.jpg
```

## 隐私说明

仓库源码与截图不包含 API key、密码、私钥或个人文件内容。使用时，文档内容只在当前浏览器中处理；发布前也建议继续避免把真实敏感文档放进示例数据或截图。

## License

MIT License，详见 [`LICENSE`](LICENSE)。
