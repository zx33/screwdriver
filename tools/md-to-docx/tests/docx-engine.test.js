"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const MarkdownDocx = require("../docx-engine.js");

const sample = [
  "# 中文标题",
  "",
  "包含 **粗体**、*斜体*、~~删除线~~、`代码` 与 [链接](https://example.com)。",
  "",
  "- 第一项",
  "- 第二项",
  "",
  "1. 步骤一",
  "2. 步骤二",
  "",
  "> 这是一段引用。",
  "",
  "```js",
  "const ready = true;",
  "```",
  "",
  "| 名称 | 状态 |",
  "| :--- | ---: |",
  "| 标题 | 支持 |"
].join("\n");

test("parses the supported Markdown block types", () => {
  const blocks = MarkdownDocx.parseMarkdown(sample);
  const types = blocks.map((block) => block.type);

  assert.ok(types.includes("heading"));
  assert.ok(types.includes("paragraph"));
  assert.ok(types.includes("listItem"));
  assert.ok(types.includes("quote"));
  assert.ok(types.includes("code"));
  assert.ok(types.includes("table"));
  assert.equal(blocks.find((block) => block.type === "table").rows.length, 1);
});

test("creates an uncompressed, self-contained DOCX package", () => {
  const bytes = MarkdownDocx.buildDocx(sample, { filename: "sample.docx" });
  const packageText = new TextDecoder().decode(bytes);

  assert.equal(bytes[0], 0x50);
  assert.equal(bytes[1], 0x4b);
  assert.ok(packageText.includes("word/document.xml"));
  assert.ok(packageText.includes("word/styles.xml"));
  assert.ok(packageText.includes("word/numbering.xml"));
  assert.ok(packageText.includes("w:pStyle w:val=\"Heading1\""));
  assert.ok(packageText.includes("w:numId w:val=\"1\""));
  assert.ok(packageText.includes("TargetMode=\"External\""));
  assert.ok(bytes.length > 5000);
});

test("keeps fenced code literal and restarts separate lists", () => {
  const markdown = "```md\n**keep the asterisks**\n```\n\n1. first\n2. second\n\nParagraph\n\n1. restart";
  const bytes = MarkdownDocx.buildDocx(markdown);
  const packageText = new TextDecoder().decode(bytes);

  assert.ok(packageText.includes("**keep the asterisks**"));
  assert.ok(packageText.includes("<w:num w:numId=\"1\"><w:abstractNumId w:val=\"1\"/>"));
  assert.ok(packageText.includes("<w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/>"));
});

test("sanitizes names without pretending to emit legacy DOC", () => {
  assert.equal(MarkdownDocx.sanitizeFilename("研究/计划.md"), "研究-计划.docx");
  assert.equal(MarkdownDocx.sanitizeFilename("draft.docx"), "draft.docx");
  assert.equal(MarkdownDocx.sanitizeFilename("  "), "document.docx");
});

test("renders escaped preview HTML", () => {
  const blocks = MarkdownDocx.parseMarkdown("# <script>alert(1)</script>\n\n**safe**");
  const html = MarkdownDocx.renderPreviewHtml(blocks);

  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(!html.includes("<script>"));
  assert.ok(html.includes("<strong>safe</strong>"));
});
