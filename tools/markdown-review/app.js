(function () {
  "use strict";

  var oldInput = document.getElementById("old-input");
  var newInput = document.getElementById("new-input");
  var diffRoot = document.getElementById("diff-root");
  var viewMode = "inline";
  var granularity = "word";
  var currentDiff = null;
  var changedRows = [];
  var currentChangeIndex = -1;

  var exampleOld = "# Markdown Review\n\n这是一个用于协同写作的 Markdown 文档。\n\n## 目标\n\n- 保持内容清晰\n- 方便团队协作\n- 记录重要修改\n\n> 所有修改都应该经过确认。\n\n```js\nconst status = 'draft';\n```";
  var exampleNew = "# Markdown Review\n\n这是一个用于团队协同写作的 Markdown 草稿文档。\n\n## 目标与范围\n\n- 保持内容清晰易读\n- 方便团队协作\n- 记录重要修改\n- 支持逐词和逐字符查看\n\n> 所有修改都应该经过确认和讨论。\n\n```js\nconst status = 'review';\n```";

  function escapeHtml(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function renderTokenSide(oldText, newText, side) {
    var operations = MarkdownDiff.diffTokens(oldText, newText, granularity);
    var html = "";

    operations.forEach(function (operation) {
      var equalText = operation.type === "equal" ? operation.a : null;
      var deletedText = operation.type === "delete" ? operation.a : null;
      var insertedText = operation.type === "insert" ? operation.b : null;

      if (operation.type === "equal") {
        html += escapeHtml(toText(equalText));
      } else if (side === "old" && operation.type === "delete") {
        html += "<del>" + escapeHtml(toText(deletedText)) + "</del>";
      } else if (side === "new" && operation.type === "insert") {
        html += "<ins>" + escapeHtml(toText(insertedText)) + "</ins>";
      }
    });

    return html || "&nbsp;";
  }

  function toText(value) {
    return Array.isArray(value) ? value.join("") : (value || "");
  }

  function lineContent(row, side) {
    var oldText = row.oldLine || "";
    var newText = row.newLine || "";
    if (row.kind === "equal") {
      return escapeHtml(side === "old" ? oldText : newText);
    }
    if (row.kind === "replace") {
      return renderTokenSide(oldText, newText, side);
    }
    if (row.kind === "delete" && side === "old") {
      return "<del>" + escapeHtml(oldText) + "</del>";
    }
    if (row.kind === "insert" && side === "new") {
      return "<ins>" + escapeHtml(newText) + "</ins>";
    }
    return "&nbsp;";
  }

  function lineClass(kind, side) {
    if (kind === "equal") {
      return "equal";
    }
    if (kind === "replace") {
      return side === "old" ? "delete" : "insert";
    }
    if (kind === "delete") {
      return side === "old" ? "delete" : "empty";
    }
    return side === "new" ? "insert" : "empty";
  }

  function renderLineNumber(value) {
    return value === null ? "" : String(value);
  }

  function renderInline(diff) {
    var oldLineNumber = 0;
    var newLineNumber = 0;
    var changeNumber = 0;
    var html = "<div class=\"review-flow\">";

    diff.rows.forEach(function (row) {
      var oldNumber = row.oldLine === null ? null : ++oldLineNumber;
      var newNumber = row.newLine === null ? null : ++newLineNumber;
      var changed = row.kind !== "equal";
      var changeAttribute = changed ? " data-change=\"" + changeNumber++ + "\"" : "";
      var displayLineNumber = row.newLine === null ? oldNumber : newNumber;
      html += "<div class=\"review-line" + (changed ? " review-line-changed change-row" : "") + "\"" + changeAttribute + ">" +
        "<span class=\"review-line-number\">" + renderLineNumber(displayLineNumber) + "</span>" +
        "<code>" + renderReviewContent(row) + "</code>" +
        "</div>";
    });

    html += "</div>";
    return html;
  }

  function renderReviewContent(row) {
    if (row.kind === "equal") {
      return escapeHtml(row.newLine || "") || "&nbsp;";
    }
    if (row.kind === "delete") {
      return "<span class=\"review-deletion\">" + (escapeHtml(row.oldLine || "") || "&nbsp;") + "</span>";
    }
    if (row.kind === "insert") {
      return "<span class=\"review-insertion\">" + (escapeHtml(row.newLine || "") || "&nbsp;") + "</span>";
    }

    var operations = MarkdownDiff.diffTokens(row.oldLine || "", row.newLine || "", granularity);
    return operations.map(function (operation) {
      if (operation.type === "equal") {
        return escapeHtml(toText(operation.a));
      }
      if (operation.type === "delete") {
        return "<span class=\"review-deletion\">" + escapeHtml(toText(operation.a)) + "</span>";
      }
      return "<span class=\"review-insertion\">" + escapeHtml(toText(operation.b)) + "</span>";
    }).join("") || "&nbsp;";
  }

  function renderSideBySide(diff) {
    var oldLineNumber = 0;
    var newLineNumber = 0;
    var changeNumber = 0;
    var html = "<div class=\"diff-lines diff-lines-side\">";

    diff.rows.forEach(function (row) {
      var oldNumber = row.oldLine === null ? null : ++oldLineNumber;
      var newNumber = row.newLine === null ? null : ++newLineNumber;
      var changed = row.kind !== "equal";
      var changeAttribute = changed ? " data-change=\"" + changeNumber++ + "\"" : "";
      html += "<div class=\"side-row\"" + changeAttribute + ">";
      html += renderSideCell(row, "old", oldNumber);
      html += renderSideCell(row, "new", newNumber);
      html += "</div>";
    });

    html += "</div>";
    return html;
  }

  function renderSideCell(row, side, lineNumber) {
    var content = lineContent(row, side);
    var kind = lineClass(row.kind, side);
    var marker = kind === "delete" ? "−" : (kind === "insert" ? "+" : "·");
    return "<div class=\"side-cell side-cell-" + kind + (kind !== "equal" && kind !== "empty" ? " change-row" : "") + "\">" +
      "<span class=\"line-number\">" + renderLineNumber(lineNumber) + "</span>" +
      "<span class=\"line-marker\">" + marker + "</span>" +
      "<code>" + content + "</code>" +
      "</div>";
  }

  function updateCounts() {
    document.getElementById("old-count").textContent = visibleLength(oldInput.value) + " 字符";
    document.getElementById("new-count").textContent = visibleLength(newInput.value) + " 字符";
  }

  function visibleLength(value) {
    return Array.from(value || "").length;
  }

  function updateSummary(diff) {
    var stats = diff.stats;
    var unit = granularity === "word" ? "词" : "字符";
    document.getElementById("added-label").textContent = "新增" + unit;
    document.getElementById("removed-label").textContent = "删除" + unit;
    document.getElementById("added-value").textContent = formatNumber(stats.added);
    document.getElementById("removed-value").textContent = formatNumber(stats.removed);
    document.getElementById("changed-lines-value").textContent = formatNumber(stats.changedLines);
    document.getElementById("hunks-value").textContent = formatNumber(stats.groups);
    document.getElementById("line-summary").textContent = "新增 " + stats.addedLines + " · 删除 " + stats.removedLines;
    document.getElementById("summary-note").textContent = stats.changedLines === 0 ? "两个版本完全一致" : "按" + unit + "统计 · 共 " + (stats.added + stats.removed) + " 个修改单位";
  }

  function formatNumber(value) {
    return new Intl.NumberFormat("zh-CN").format(value);
  }

  function compare() {
    updateCounts();
    currentDiff = MarkdownDiff.buildDiff(oldInput.value, newInput.value, granularity);
    updateSummary(currentDiff);
    currentChangeIndex = -1;
    renderDiff();
    var status = document.getElementById("compare-status");
    status.textContent = currentDiff.stats.changedLines === 0 ? "没有发现修改" : "已完成比较";
    status.classList.toggle("is-complete", currentDiff.stats.changedLines > 0);
  }

  function renderDiff() {
    if (!currentDiff) {
      return;
    }
    if (currentDiff.stats.changedLines === 0) {
      diffRoot.innerHTML = "<div class=\"empty-state empty-state-success\"><div class=\"empty-icon\" aria-hidden=\"true\">✓</div><h3>两个版本完全一致</h3><p>没有检测到需要审阅的修改。</p></div>";
      updateNavigation();
      return;
    }

    diffRoot.innerHTML = viewMode === "inline" ? renderInline(currentDiff) : renderSideBySide(currentDiff);
    var seenChanges = new Set();
    changedRows = Array.from(diffRoot.querySelectorAll("[data-change]")).filter(function (row) {
      var changeId = row.getAttribute("data-change");
      if (seenChanges.has(changeId)) {
        return false;
      }
      seenChanges.add(changeId);
      return true;
    });
    updateNavigation();
  }

  function updateNavigation() {
    var total = changedRows.length;
    document.getElementById("change-position").textContent = total === 0 ? "0 / 0" : (currentChangeIndex < 0 ? "— / " + total : (currentChangeIndex + 1) + " / " + total);
  }

  function moveToChange(direction) {
    if (!changedRows.length) {
      return;
    }
    currentChangeIndex = (currentChangeIndex + direction + changedRows.length) % changedRows.length;
    diffRoot.querySelectorAll(".is-focused").forEach(function (row) { row.classList.remove("is-focused"); });
    var target = changedRows[currentChangeIndex];
    var changeId = target.getAttribute("data-change");
    diffRoot.querySelectorAll('[data-change="' + changeId + '"]').forEach(function (row) {
      row.classList.add("is-focused");
    });
    target.scrollIntoView({ behavior: "smooth", block: "center" });
    updateNavigation();
  }

  function setViewMode(nextMode) {
    viewMode = nextMode;
    document.querySelectorAll("[data-view-mode]").forEach(function (button) {
      button.classList.toggle("is-active", button.dataset.viewMode === viewMode);
    });
    renderDiff();
  }

  function setGranularity(nextGranularity) {
    granularity = nextGranularity;
    document.querySelectorAll("[data-granularity]").forEach(function (button) {
      button.classList.toggle("is-active", button.dataset.granularity === granularity);
    });
    compare();
  }

  function loadExample() {
    oldInput.value = exampleOld;
    newInput.value = exampleNew;
    compare();
  }

  function clearAll() {
    oldInput.value = "";
    newInput.value = "";
    compare();
    document.getElementById("compare-status").textContent = "等待输入";
    document.getElementById("compare-status").classList.remove("is-complete");
  }

  oldInput.addEventListener("input", compare);
  newInput.addEventListener("input", compare);
  document.getElementById("compare-button").addEventListener("click", compare);
  document.getElementById("load-example").addEventListener("click", loadExample);
  document.getElementById("clear-all").addEventListener("click", clearAll);
  document.querySelectorAll("[data-view-mode]").forEach(function (button) {
    button.addEventListener("click", function () { setViewMode(button.dataset.viewMode); });
  });
  document.querySelectorAll("[data-granularity]").forEach(function (button) {
    button.addEventListener("click", function () { setGranularity(button.dataset.granularity); });
  });
  document.getElementById("previous-change").addEventListener("click", function () { moveToChange(-1); });
  document.getElementById("next-change").addEventListener("click", function () { moveToChange(1); });

  loadExample();
}());
