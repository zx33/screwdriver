(function () {
  "use strict";

  var source = document.getElementById("markdown-source");
  var preview = document.getElementById("word-preview");
  var filename = document.getElementById("docx-filename");
  var fileInput = document.getElementById("markdown-file");
  var dropZone = document.getElementById("markdown-drop-zone");
  var status = document.getElementById("export-status");

  var example = "# Markdown → Word\n\n这是一份由 **Screwdriver** 在浏览器本地生成的 Word 文档。\n\n## 为什么做这个小工具\n\n- 不上传原文\n- 不安装大型软件\n- 导出后仍然可以在 Word 里继续编辑\n\n## 支持的内容\n\n1. 标题、段落与 *强调*\n2. [网页链接](https://example.com) 与 `行内代码`\n3. 引用、代码块和简单表格\n\n> 小工具不必很重，能把眼前的螺丝拧紧就行。\n\n```js\nconst output = MarkdownDocx.buildDocx(markdown);\n```\n\n| 格式 | 状态 | 说明 |\n| :--- | :---: | ---: |\n| 标题 | 支持 | 1–6 级 |\n| 列表 | 支持 | 有序 / 无序 |\n| 图片 | 简化 | 保留替代文字 |";

  function update() {
    var blocks = MarkdownDocx.parseMarkdown(source.value);
    preview.innerHTML = MarkdownDocx.renderPreviewHtml(blocks);
    document.getElementById("markdown-count").textContent = Array.from(source.value).length + " 字符";
    document.getElementById("block-count").textContent = blocks.length + " 个内容块";
    status.textContent = source.value.trim() ? "准备就绪 · 可导出 .docx" : "等待输入 Markdown";
    status.classList.remove("is-success", "is-error");
  }

  function setFilenameFromFile(file) {
    if (file && file.name) {
      filename.value = MarkdownDocx.sanitizeFilename(file.name);
    }
  }

  function readMarkdownFile(file) {
    if (!file) { return; }
    if (file.size > 5 * 1024 * 1024) {
      status.textContent = "文件超过 5 MB，第一版先不处理这么大的文档。";
      status.classList.add("is-error");
      return;
    }
    var reader = new FileReader();
    reader.onload = function () {
      source.value = String(reader.result || "");
      setFilenameFromFile(file);
      update();
      status.textContent = "已读取 " + file.name + " · 内容仍在本地";
      status.classList.add("is-success");
    };
    reader.onerror = function () {
      status.textContent = "没有读到这个文件，请再试一次。";
      status.classList.add("is-error");
    };
    reader.readAsText(file);
  }

  function exportDocx() {
    if (!source.value.trim()) {
      status.textContent = "先放一点 Markdown 进来，再导出。";
      status.classList.add("is-error");
      source.focus();
      return;
    }
    try {
      var safeName = MarkdownDocx.sanitizeFilename(filename.value);
      filename.value = safeName;
      var bytes = MarkdownDocx.buildDocx(source.value, { filename: safeName });
      var blob = new Blob([bytes], { type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" });
      var url = URL.createObjectURL(blob);
      var anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = safeName;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      window.setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
      status.textContent = "已生成 " + safeName + " · " + formatBytes(bytes.length);
      status.classList.remove("is-error");
      status.classList.add("is-success");
    } catch (error) {
      status.textContent = "导出失败：" + (error && error.message ? error.message : "未知错误");
      status.classList.remove("is-success");
      status.classList.add("is-error");
    }
  }

  function formatBytes(bytes) {
    if (bytes < 1024) { return bytes + " B"; }
    return (bytes / 1024).toFixed(1) + " KB";
  }

  source.addEventListener("input", update);
  filename.addEventListener("blur", function () { filename.value = MarkdownDocx.sanitizeFilename(filename.value); });
  fileInput.addEventListener("change", function () { readMarkdownFile(fileInput.files[0]); });
  document.getElementById("export-docx").addEventListener("click", exportDocx);
  document.getElementById("load-converter-example").addEventListener("click", function () {
    source.value = example;
    filename.value = "markdown-to-word-example.docx";
    update();
  });
  document.getElementById("clear-converter").addEventListener("click", function () {
    source.value = "";
    filename.value = "markdown-document.docx";
    fileInput.value = "";
    update();
    source.focus();
  });

  ["dragenter", "dragover"].forEach(function (eventName) {
    dropZone.addEventListener(eventName, function (event) {
      event.preventDefault();
      dropZone.classList.add("is-dragging");
    });
  });
  ["dragleave", "drop"].forEach(function (eventName) {
    dropZone.addEventListener(eventName, function (event) {
      event.preventDefault();
      dropZone.classList.remove("is-dragging");
    });
  });
  dropZone.addEventListener("drop", function (event) {
    readMarkdownFile(event.dataTransfer.files[0]);
  });

  source.value = example;
  update();
}());
