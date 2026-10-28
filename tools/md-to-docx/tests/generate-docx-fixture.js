"use strict";

const fs = require("node:fs");
const path = require("node:path");
const MarkdownDocx = require("../docx-engine.js");

const output = process.argv[2];
if (!output) {
  throw new Error("Provide an output .docx path");
}

const markdown = [
  "# Markdown → Word 验收样例",
  "",
  "这份文档用于检查 **中文排版**、*强调*、~~删除线~~、`行内代码` 与 [外部链接](https://example.com)。",
  "",
  "## 列表与引用",
  "",
  "- 浏览器本地生成，不上传原文",
  "- 使用真正的 Word 段落和列表",
  "  - 嵌套项目也保留层级",
  "",
  "1. 输入 Markdown",
  "2. 检查近似预览",
  "3. 导出 DOCX",
  "",
  "> 小工具不必很重，能把眼前的螺丝拧紧就行。",
  "",
  "## 代码块",
  "",
  "```js",
  "const bytes = MarkdownDocx.buildDocx(markdown);",
  "download(bytes, 'document.docx');",
  "```",
  "",
  "## 简单表格",
  "",
  "| 格式 | 当前支持 | 输出方式 |",
  "| :--- | :---: | ---: |",
  "| 标题 | 是 | Word 标题样式 |",
  "| 列表 | 是 | 原生编号定义 |",
  "| 表格 | 是 | 固定列宽表格 |",
  "| 图片 | 简化 | 保留替代文字 |",
  "",
  "---",
  "",
  "结论：如果本页没有文字截断、重叠或表格越界，第一版的基础排版即可通过。"
].join("\n");

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, MarkdownDocx.buildDocx(markdown, { title: "Markdown → Word 验收样例" }));
process.stdout.write(output + "\n");
