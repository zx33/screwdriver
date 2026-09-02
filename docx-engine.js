(function (root) {
  "use strict";

  var ZIP_UTF8_FLAG = 0x0800;
  var WORD_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml";
  var RELATIONSHIP_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
  var crcTable = null;

  function normalizeText(value) {
    return String(value || "").replace(/\r\n?/g, "\n");
  }

  function cleanXmlText(value) {
    return String(value === undefined || value === null ? "" : value)
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");
  }

  function escapeXml(value) {
    return cleanXmlText(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
  }

  function escapeHtml(value) {
    return cleanXmlText(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function splitTableRow(line) {
    var value = line.trim();
    if (value.charAt(0) === "|") {
      value = value.slice(1);
    }
    if (value.charAt(value.length - 1) === "|") {
      value = value.slice(0, -1);
    }
    return value.split(/(?<!\\)\|/).map(function (cell) {
      return cell.trim().replace(/\\\|/g, "|");
    });
  }

  function isTableDivider(line) {
    var cells = splitTableRow(line);
    return cells.length > 0 && cells.every(function (cell) {
      return /^:?-{3,}:?$/.test(cell.replace(/\s/g, ""));
    });
  }

  function isHorizontalRule(line) {
    return /^\s{0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$/.test(line);
  }

  function listMatch(line) {
    return line.match(/^(\s{0,12})([-+*]|\d+[.)])\s+(.+)$/);
  }

  function startsBlock(lines, index) {
    var line = lines[index] || "";
    var next = lines[index + 1] || "";
    return /^\s{0,3}(?:#{1,6})\s+/.test(line) ||
      /^\s{0,3}(?:```|~~~)/.test(line) ||
      /^\s{0,3}>/.test(line) ||
      Boolean(listMatch(line)) ||
      isHorizontalRule(line) ||
      (line.indexOf("|") !== -1 && isTableDivider(next));
  }

  function parseMarkdown(markdown) {
    var lines = normalizeText(markdown).split("\n");
    var blocks = [];
    var index = 0;
    var listSequence = 0;

    while (index < lines.length) {
      var line = lines[index];
      if (!line.trim()) {
        index += 1;
        continue;
      }

      var fence = line.match(/^\s{0,3}(`{3,}|~{3,})\s*([^\s]*)\s*$/);
      if (fence) {
        var fenceMarker = fence[1];
        var language = fence[2] || "";
        var codeLines = [];
        index += 1;
        while (index < lines.length && !new RegExp("^\\s{0,3}" + fenceMarker.charAt(0) + "{" + fenceMarker.length + ",}\\s*$").test(lines[index])) {
          codeLines.push(lines[index]);
          index += 1;
        }
        if (index < lines.length) {
          index += 1;
        }
        blocks.push({ type: "code", language: language, text: codeLines.join("\n") });
        continue;
      }

      var heading = line.match(/^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$/);
      if (heading) {
        blocks.push({ type: "heading", level: heading[1].length, text: heading[2] });
        index += 1;
        continue;
      }

      if (isHorizontalRule(line)) {
        blocks.push({ type: "rule" });
        index += 1;
        continue;
      }

      if (line.indexOf("|") !== -1 && index + 1 < lines.length && isTableDivider(lines[index + 1])) {
        var headers = splitTableRow(line);
        var aligns = splitTableRow(lines[index + 1]).map(function (cell) {
          var left = cell.charAt(0) === ":";
          var right = cell.charAt(cell.length - 1) === ":";
          return left && right ? "center" : (right ? "right" : "left");
        });
        var rows = [];
        index += 2;
        while (index < lines.length && lines[index].trim() && lines[index].indexOf("|") !== -1 && !startsBlock(lines, index)) {
          rows.push(splitTableRow(lines[index]));
          index += 1;
        }
        blocks.push({ type: "table", headers: headers, aligns: aligns, rows: rows });
        continue;
      }

      if (/^\s{0,3}>/.test(line)) {
        var quoteLines = [];
        while (index < lines.length && /^\s{0,3}>/.test(lines[index])) {
          quoteLines.push(lines[index].replace(/^\s{0,3}>\s?/, ""));
          index += 1;
        }
        blocks.push({ type: "quote", text: quoteLines.join("\n") });
        continue;
      }

      var item = listMatch(line);
      if (item) {
        listSequence += 1;
        var groupOrdered = /^\d/.test(item[2]);
        while (index < lines.length && (item = listMatch(lines[index])) && /^\d/.test(item[2]) === groupOrdered) {
          var marker = item[2];
          blocks.push({
            type: "listItem",
            ordered: /^\d/.test(marker),
            level: Math.min(8, Math.floor(item[1].replace(/\t/g, "  ").length / 2)),
            numId: listSequence,
            text: item[3]
          });
          index += 1;
        }
        continue;
      }

      var paragraphLines = [line.trim()];
      index += 1;
      while (index < lines.length && lines[index].trim() && !startsBlock(lines, index)) {
        paragraphLines.push(lines[index].trim());
        index += 1;
      }
      blocks.push({ type: "paragraph", text: paragraphLines.join(" ") });
    }

    return blocks;
  }

  function sameRunStyle(left, right) {
    return left.bold === right.bold && left.italic === right.italic && left.strike === right.strike &&
      left.code === right.code && left.link === right.link && left.break === right.break;
  }

  function appendRun(runs, run) {
    if (!run.break && !run.text) {
      return;
    }
    var previous = runs[runs.length - 1];
    if (previous && !run.break && !previous.break && sameRunStyle(previous, run)) {
      previous.text += run.text;
    } else {
      runs.push(run);
    }
  }

  function parseInline(text, inherited) {
    var value = String(text || "");
    var base = inherited || {};
    var runs = [];
    var index = 0;

    function pushText(content, extra) {
      appendRun(runs, {
        text: content,
        bold: Boolean(extra && extra.bold || base.bold),
        italic: Boolean(extra && extra.italic || base.italic),
        strike: Boolean(extra && extra.strike || base.strike),
        code: Boolean(extra && extra.code || base.code),
        link: extra && extra.link || base.link || null
      });
    }

    function pushNested(content, extra) {
      parseInline(content, {
        bold: Boolean(extra && extra.bold || base.bold),
        italic: Boolean(extra && extra.italic || base.italic),
        strike: Boolean(extra && extra.strike || base.strike),
        code: Boolean(extra && extra.code || base.code),
        link: extra && extra.link || base.link || null
      }).forEach(function (run) { appendRun(runs, run); });
    }

    while (index < value.length) {
      if (value.charAt(index) === "\\" && index + 1 < value.length && /[\\`*_[\]()]|!/.test(value.charAt(index + 1))) {
        pushText(value.charAt(index + 1));
        index += 2;
        continue;
      }
      if (value.charAt(index) === "\n") {
        appendRun(runs, { break: true, text: "" });
        index += 1;
        continue;
      }

      var codeMarker = value.charAt(index) === "`" ? "`" : null;
      if (codeMarker) {
        var codeEnd = value.indexOf(codeMarker, index + 1);
        if (codeEnd !== -1) {
          pushText(value.slice(index + 1, codeEnd), { code: true });
          index = codeEnd + 1;
          continue;
        }
      }

      var image = value.slice(index).match(/^!\[([^\]]*)\]\(([^)]+)\)/);
      if (image) {
        pushText("[图片: " + (image[1] || image[2]) + "]", { italic: true });
        index += image[0].length;
        continue;
      }

      var link = value.slice(index).match(/^\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/);
      if (link) {
        pushNested(link[1], { link: safeHref(link[2]) });
        index += link[0].length;
        continue;
      }

      var pair = value.slice(index, index + 2);
      var close;
      if (pair === "**" || pair === "__") {
        close = value.indexOf(pair, index + 2);
        if (close !== -1) {
          pushNested(value.slice(index + 2, close), { bold: true });
          index = close + 2;
          continue;
        }
      }
      if (pair === "~~") {
        close = value.indexOf(pair, index + 2);
        if (close !== -1) {
          pushNested(value.slice(index + 2, close), { strike: true });
          index = close + 2;
          continue;
        }
      }

      var marker = value.charAt(index);
      if (marker === "*" || marker === "_") {
        close = value.indexOf(marker, index + 1);
        if (close > index + 1) {
          pushNested(value.slice(index + 1, close), { italic: true });
          index = close + 1;
          continue;
        }
      }

      var next = index + 1;
      while (next < value.length && "\\\n`!*_[~".indexOf(value.charAt(next)) === -1) {
        next += 1;
      }
      pushText(value.slice(index, next));
      index = next;
    }
    return runs;
  }

  function safeHref(value) {
    var href = String(value || "").trim();
    return /^(?:https?:\/\/|mailto:)/i.test(href) ? href : null;
  }

  function textElement(text) {
    var value = cleanXmlText(text);
    var preserve = /^\s|\s$|\s{2,}/.test(value) ? " xml:space=\"preserve\"" : "";
    return "<w:t" + preserve + ">" + escapeXml(value) + "</w:t>";
  }

  function relationshipId(state, href) {
    if (!href) {
      return null;
    }
    if (state.linkIds[href]) {
      return state.linkIds[href];
    }
    var id = "rId" + (state.rels.length + 4);
    state.linkIds[href] = id;
    state.rels.push({ id: id, href: href });
    return id;
  }

  function runXml(run, state) {
    if (run.break) {
      return "<w:r><w:br/></w:r>";
    }
    var properties = [];
    if (run.bold) { properties.push("<w:b/>"); }
    if (run.italic) { properties.push("<w:i/>"); }
    if (run.strike) { properties.push("<w:strike/>"); }
    if (run.code) { properties.push("<w:rStyle w:val=\"InlineCode\"/>"); }
    var relationId = relationshipId(state, run.link);
    if (relationId) { properties.push("<w:rStyle w:val=\"Hyperlink\"/>"); }
    var xml = "<w:r>" + (properties.length ? "<w:rPr>" + properties.join("") + "</w:rPr>" : "") + textElement(run.text) + "</w:r>";
    return relationId ? "<w:hyperlink r:id=\"" + relationId + "\" w:history=\"1\">" + xml + "</w:hyperlink>" : xml;
  }

  function inlineXml(text, state, forceBold) {
    var runs = parseInline(text, forceBold ? { bold: true } : {});
    if (!runs.length) {
      return "<w:r><w:t></w:t></w:r>";
    }
    return runs.map(function (run) { return runXml(run, state); }).join("");
  }

  function literalXml(text) {
    return String(text || "").split("\n").map(function (line, index) {
      return (index ? "<w:r><w:br/></w:r>" : "") + "<w:r>" + textElement(line) + "</w:r>";
    }).join("");
  }

  function paragraphXml(block, state) {
    var properties = [];
    if (block.type === "heading") {
      properties.push("<w:pStyle w:val=\"Heading" + block.level + "\"/>");
    } else if (block.type === "quote") {
      properties.push("<w:pStyle w:val=\"Quote\"/>");
    } else if (block.type === "code") {
      properties.push("<w:pStyle w:val=\"CodeBlock\"/>");
    } else if (block.type === "listItem") {
      properties.push("<w:pStyle w:val=\"ListParagraph\"/>");
      properties.push("<w:numPr><w:ilvl w:val=\"" + block.level + "\"/><w:numId w:val=\"" + block.numId + "\"/></w:numPr>");
    } else if (block.type === "rule") {
      properties.push("<w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"6\" w:color=\"D7DEEA\"/></w:pBdr>");
      properties.push("<w:spacing w:after=\"160\"/>");
    }
    var content = block.type === "rule" ? "<w:r><w:t></w:t></w:r>" :
      (block.type === "code" ? literalXml(block.text) : inlineXml(block.text, state, false));
    return "<w:p>" + (properties.length ? "<w:pPr>" + properties.join("") + "</w:pPr>" : "") + content + "</w:p>";
  }

  function tableWidths(block) {
    var count = Math.max(1, block.headers.length);
    var weights = [];
    for (var column = 0; column < count; column += 1) {
      var maxLength = cleanXmlText(block.headers[column] || "").length;
      block.rows.forEach(function (row) {
        maxLength = Math.max(maxLength, cleanXmlText(row[column] || "").length);
      });
      weights.push(Math.min(36, Math.max(8, maxLength)));
    }
    var totalWeight = weights.reduce(function (sum, value) { return sum + value; }, 0);
    var widths = weights.map(function (weight) { return Math.floor(9360 * weight / totalWeight); });
    widths[widths.length - 1] += 9360 - widths.reduce(function (sum, value) { return sum + value; }, 0);
    return widths;
  }

  function cellXml(value, width, align, header, state) {
    var fill = header ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F4F7\"/>" : "";
    var alignment = align && align !== "left" ? "<w:jc w:val=\"" + align + "\"/>" : "";
    var paragraphProperties = "<w:pPr><w:spacing w:after=\"0\"/>" + alignment + "</w:pPr>";
    return "<w:tc><w:tcPr><w:tcW w:w=\"" + width + "\" w:type=\"dxa\"/>" + fill + "<w:vAlign w:val=\"center\"/></w:tcPr>" +
      "<w:p>" + paragraphProperties + inlineXml(value, state, header) + "</w:p></w:tc>";
  }

  function tableXml(block, state) {
    var widths = tableWidths(block);
    var grid = widths.map(function (width) { return "<w:gridCol w:w=\"" + width + "\"/>"; }).join("");
    var tableProperties = "<w:tblPr><w:tblW w:w=\"9360\" w:type=\"dxa\"/><w:tblInd w:w=\"0\" w:type=\"dxa\"/>" +
      "<w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:top w:w=\"80\" w:type=\"dxa\"/><w:start w:w=\"120\" w:type=\"dxa\"/>" +
      "<w:bottom w:w=\"80\" w:type=\"dxa\"/><w:end w:w=\"120\" w:type=\"dxa\"/></w:tblCellMar>" +
      "<w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:color=\"D7DEEA\"/><w:left w:val=\"single\" w:sz=\"4\" w:color=\"D7DEEA\"/>" +
      "<w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"D7DEEA\"/><w:right w:val=\"single\" w:sz=\"4\" w:color=\"D7DEEA\"/>" +
      "<w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"E5EAF1\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:color=\"E5EAF1\"/></w:tblBorders></w:tblPr>";
    var headerCells = widths.map(function (width, index) {
      return cellXml(block.headers[index] || "", width, block.aligns[index], true, state);
    }).join("");
    var rows = "<w:tr><w:trPr><w:tblHeader/></w:trPr>" + headerCells + "</w:tr>";
    block.rows.forEach(function (row) {
      rows += "<w:tr>" + widths.map(function (width, index) {
        return cellXml(row[index] || "", width, block.aligns[index], false, state);
      }).join("") + "</w:tr>";
    });
    return "<w:tbl>" + tableProperties + "<w:tblGrid>" + grid + "</w:tblGrid>" + rows + "</w:tbl>" +
      "<w:p><w:pPr><w:spacing w:after=\"80\"/></w:pPr></w:p>";
  }

  function documentXml(blocks, state) {
    var body = blocks.map(function (block) {
      return block.type === "table" ? tableXml(block, state) : paragraphXml(block, state);
    }).join("");
    if (!body) {
      body = "<w:p/>";
    }
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
      "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"" + RELATIONSHIP_NS + "\"><w:body>" + body +
      "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>" +
      "<w:cols w:space=\"720\"/><w:docGrid w:linePitch=\"360\"/></w:sectPr></w:body></w:document>";
  }

  function stylesXml() {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
      "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
      "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Arial Unicode MS\" w:hAnsi=\"Arial Unicode MS\" w:eastAsia=\"Arial Unicode MS\" w:cs=\"Arial Unicode MS\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/><w:lang w:val=\"zh-CN\" w:eastAsia=\"zh-CN\"/></w:rPr></w:rPrDefault>" +
      "<w:pPrDefault><w:pPr><w:spacing w:after=\"120\" w:line=\"264\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>" +
      styleXml("Normal", "Normal", null, "qFormat", "<w:spacing w:after=\"120\" w:line=\"264\" w:lineRule=\"auto\"/>", "") +
      styleXml("Heading1", "Heading 1", "Normal", "qFormat", "<w:keepNext/><w:keepLines/><w:spacing w:before=\"320\" w:after=\"160\"/><w:outlineLvl w:val=\"0\"/>", "<w:b/><w:color w:val=\"2E74B5\"/><w:sz w:val=\"32\"/><w:szCs w:val=\"32\"/>") +
      styleXml("Heading2", "Heading 2", "Normal", "qFormat", "<w:keepNext/><w:keepLines/><w:spacing w:before=\"240\" w:after=\"120\"/><w:outlineLvl w:val=\"1\"/>", "<w:b/><w:color w:val=\"2E74B5\"/><w:sz w:val=\"26\"/><w:szCs w:val=\"26\"/>") +
      styleXml("Heading3", "Heading 3", "Normal", "qFormat", "<w:keepNext/><w:keepLines/><w:spacing w:before=\"160\" w:after=\"80\"/><w:outlineLvl w:val=\"2\"/>", "<w:b/><w:color w:val=\"1F4D78\"/><w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/>") +
      styleXml("Heading4", "Heading 4", "Normal", "qFormat", "<w:keepNext/><w:spacing w:before=\"140\" w:after=\"60\"/><w:outlineLvl w:val=\"3\"/>", "<w:b/><w:sz w:val=\"22\"/>") +
      styleXml("Heading5", "Heading 5", "Normal", "qFormat", "<w:keepNext/><w:spacing w:before=\"120\" w:after=\"40\"/><w:outlineLvl w:val=\"4\"/>", "<w:b/><w:i/><w:sz w:val=\"21\"/>") +
      styleXml("Heading6", "Heading 6", "Normal", "qFormat", "<w:keepNext/><w:spacing w:before=\"100\" w:after=\"40\"/><w:outlineLvl w:val=\"5\"/>", "<w:i/><w:sz w:val=\"21\"/>") +
      styleXml("ListParagraph", "List Paragraph", "Normal", "qFormat", "<w:spacing w:after=\"80\"/><w:contextualSpacing/>", "") +
      styleXml("Quote", "Quote", "Normal", "qFormat", "<w:ind w:left=\"360\" w:right=\"180\"/><w:spacing w:before=\"80\" w:after=\"120\"/><w:pBdr><w:left w:val=\"single\" w:sz=\"18\" w:space=\"10\" w:color=\"A875D1\"/></w:pBdr>", "<w:i/><w:color w:val=\"555555\"/>") +
      styleXml("CodeBlock", "Code Block", "Normal", "qFormat", "<w:ind w:left=\"240\" w:right=\"240\"/><w:spacing w:before=\"80\" w:after=\"140\" w:line=\"240\" w:lineRule=\"auto\"/><w:shd w:val=\"clear\" w:fill=\"F5F7FA\"/>", "<w:rFonts w:ascii=\"Consolas\" w:hAnsi=\"Consolas\" w:eastAsia=\"Arial Unicode MS\"/><w:sz w:val=\"19\"/><w:szCs w:val=\"19\"/>") +
      characterStyleXml("Hyperlink", "Hyperlink", "<w:color w:val=\"356DF3\"/><w:u w:val=\"single\"/>") +
      characterStyleXml("InlineCode", "Inline Code", "<w:rFonts w:ascii=\"Consolas\" w:hAnsi=\"Consolas\" w:eastAsia=\"Arial Unicode MS\"/><w:color w:val=\"7540AE\"/><w:sz w:val=\"20\"/><w:shd w:val=\"clear\" w:fill=\"F5F1FA\"/>") +
      "</w:styles>";
  }

  function styleXml(id, name, basedOn, extra, paragraphProperties, runProperties) {
    return "<w:style w:type=\"paragraph\" w:styleId=\"" + id + "\"><w:name w:val=\"" + name + "\"/>" +
      (basedOn ? "<w:basedOn w:val=\"" + basedOn + "\"/>" : "") + "<w:next w:val=\"Normal\"/>" +
      (extra === "qFormat" ? "<w:qFormat/>" : "") + "<w:pPr>" + paragraphProperties + "</w:pPr><w:rPr>" + runProperties + "</w:rPr></w:style>";
  }

  function characterStyleXml(id, name, runProperties) {
    return "<w:style w:type=\"character\" w:customStyle=\"1\" w:styleId=\"" + id + "\"><w:name w:val=\"" + name + "\"/><w:basedOn w:val=\"DefaultParagraphFont\"/><w:uiPriority w:val=\"99\"/><w:unhideWhenUsed/><w:rPr>" + runProperties + "</w:rPr></w:style>";
  }

  function numberingXml(blocks) {
    var bulletLevels = "";
    var numberLevels = "";
    for (var level = 0; level < 9; level += 1) {
      var left = 720 + level * 360;
      bulletLevels += "<w:lvl w:ilvl=\"" + level + "\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"" + (level % 3 === 1 ? "○" : (level % 3 === 2 ? "■" : "●")) + "\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"" + left + "\"/></w:tabs><w:ind w:left=\"" + left + "\" w:hanging=\"360\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:hint=\"default\"/></w:rPr></w:lvl>";
      numberLevels += "<w:lvl w:ilvl=\"" + level + "\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%" + (level + 1) + ".\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"" + left + "\"/></w:tabs><w:ind w:left=\"" + left + "\" w:hanging=\"360\"/></w:pPr></w:lvl>";
    }
    var listInstances = [];
    var seen = Object.create(null);
    blocks.forEach(function (block) {
      if (block.type === "listItem" && !seen[block.numId]) {
        seen[block.numId] = true;
        listInstances.push("<w:num w:numId=\"" + block.numId + "\"><w:abstractNumId w:val=\"" + (block.ordered ? 1 : 0) + "\"/></w:num>");
      }
    });
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" +
      "<w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"multilevel\"/>" + bulletLevels + "</w:abstractNum>" +
      "<w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"multilevel\"/>" + numberLevels + "</w:abstractNum>" +
      listInstances.join("") + "</w:numbering>";
  }

  function settingsXml() {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:zoom w:percent=\"100\"/><w:defaultTabStop w:val=\"720\"/><w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat></w:settings>";
  }

  function contentTypesXml() {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"" + WORD_CONTENT_TYPE + "\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/><Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/></Types>";
  }

  function packageRelationshipsXml() {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>";
  }

  function documentRelationshipsXml(state) {
    var links = state.rels.map(function (relation) {
      return "<Relationship Id=\"" + relation.id + "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"" + escapeXml(relation.href) + "\" TargetMode=\"External\"/>";
    }).join("");
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>" + links + "</Relationships>";
  }

  function corePropertiesXml(title) {
    var timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:title>" + escapeXml(title) + "</dc:title><dc:creator>Screwdriver</dc:creator><cp:lastModifiedBy>Screwdriver</cp:lastModifiedBy><dcterms:created xsi:type=\"dcterms:W3CDTF\">" + timestamp + "</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">" + timestamp + "</dcterms:modified></cp:coreProperties>";
  }

  function appPropertiesXml() {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>Screwdriver Markdown to Word</Application><AppVersion>1.0</AppVersion></Properties>";
  }

  function deriveTitle(blocks, fallback) {
    var heading = blocks.find(function (block) { return block.type === "heading"; });
    return heading ? parseInline(heading.text).map(function (run) { return run.text || ""; }).join("") : (fallback || "Markdown document");
  }

  function buildDocx(markdown, options) {
    var settings = options || {};
    var blocks = parseMarkdown(markdown);
    var state = { rels: [], linkIds: Object.create(null) };
    var title = settings.title || deriveTitle(blocks, settings.filename);
    var document = documentXml(blocks, state);
    return createZip([
      { name: "[Content_Types].xml", data: contentTypesXml() },
      { name: "_rels/.rels", data: packageRelationshipsXml() },
      { name: "docProps/core.xml", data: corePropertiesXml(title) },
      { name: "docProps/app.xml", data: appPropertiesXml() },
      { name: "word/document.xml", data: document },
      { name: "word/_rels/document.xml.rels", data: documentRelationshipsXml(state) },
      { name: "word/styles.xml", data: stylesXml() },
      { name: "word/numbering.xml", data: numberingXml(blocks) },
      { name: "word/settings.xml", data: settingsXml() }
    ]);
  }

  function sanitizeFilename(value) {
    var filename = String(value || "document").trim().replace(/\.md$/i, "").replace(/\.docx$/i, "");
    filename = filename.replace(/[\\/:*?"<>|\u0000-\u001F]/g, "-").replace(/\s+/g, " ").replace(/[. ]+$/g, "");
    return (filename || "document") + ".docx";
  }

  function renderInlineHtml(text) {
    return parseInline(text).map(function (run) {
      if (run.break) { return "<br>"; }
      var content = escapeHtml(run.text);
      if (run.code) { content = "<code>" + content + "</code>"; }
      if (run.bold) { content = "<strong>" + content + "</strong>"; }
      if (run.italic) { content = "<em>" + content + "</em>"; }
      if (run.strike) { content = "<s>" + content + "</s>"; }
      if (run.link) { content = "<a href=\"" + escapeHtml(run.link) + "\" target=\"_blank\" rel=\"noreferrer\">" + content + "</a>"; }
      return content;
    }).join("");
  }

  function renderPreviewHtml(blocks) {
    var html = "";
    var listType = null;
    function closeList() {
      if (listType) {
        html += listType === "ol" ? "</ol>" : "</ul>";
        listType = null;
      }
    }
    blocks.forEach(function (block) {
      if (block.type === "listItem") {
        var nextType = block.ordered ? "ol" : "ul";
        if (listType !== nextType) {
          closeList();
          listType = nextType;
          html += nextType === "ol" ? "<ol>" : "<ul>";
        }
        html += "<li>" + renderInlineHtml(block.text) + "</li>";
        return;
      }
      closeList();
      if (block.type === "heading") {
        html += "<h" + block.level + ">" + renderInlineHtml(block.text) + "</h" + block.level + ">";
      } else if (block.type === "paragraph") {
        html += "<p>" + renderInlineHtml(block.text) + "</p>";
      } else if (block.type === "quote") {
        html += "<blockquote>" + renderInlineHtml(block.text) + "</blockquote>";
      } else if (block.type === "code") {
        html += "<pre><code>" + escapeHtml(block.text) + "</code></pre>";
      } else if (block.type === "rule") {
        html += "<hr>";
      } else if (block.type === "table") {
        html += "<div class=\"preview-table-wrap\"><table><thead><tr>" + block.headers.map(function (cell, index) {
          return "<th style=\"text-align:" + block.aligns[index] + "\">" + renderInlineHtml(cell) + "</th>";
        }).join("") + "</tr></thead><tbody>" + block.rows.map(function (row) {
          return "<tr>" + block.headers.map(function (_, index) {
            return "<td style=\"text-align:" + block.aligns[index] + "\">" + renderInlineHtml(row[index] || "") + "</td>";
          }).join("") + "</tr>";
        }).join("") + "</tbody></table></div>";
      }
    });
    closeList();
    return html || "<div class=\"preview-empty\">在左侧输入 Markdown，这里会显示 Word 排版预览。</div>";
  }

  function getCrcTable() {
    if (crcTable) { return crcTable; }
    crcTable = [];
    for (var index = 0; index < 256; index += 1) {
      var value = index;
      for (var bit = 0; bit < 8; bit += 1) {
        value = (value & 1) ? (0xEDB88320 ^ (value >>> 1)) : (value >>> 1);
      }
      crcTable[index] = value >>> 0;
    }
    return crcTable;
  }

  function crc32(bytes) {
    var crc = 0xFFFFFFFF;
    var table = getCrcTable();
    for (var index = 0; index < bytes.length; index += 1) {
      crc = table[(crc ^ bytes[index]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function pushU16(target, value) {
    target.push(value & 0xFF, (value >>> 8) & 0xFF);
  }

  function pushU32(target, value) {
    target.push(value & 0xFF, (value >>> 8) & 0xFF, (value >>> 16) & 0xFF, (value >>> 24) & 0xFF);
  }

  function dosDateTime(date) {
    var year = Math.max(1980, date.getFullYear());
    return {
      time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2),
      date: ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate()
    };
  }

  function toBytes(value) {
    return value instanceof Uint8Array ? value : new TextEncoder().encode(String(value));
  }

  function joinBytes(chunks) {
    var size = chunks.reduce(function (sum, chunk) { return sum + chunk.length; }, 0);
    var result = new Uint8Array(size);
    var offset = 0;
    chunks.forEach(function (chunk) {
      result.set(chunk, offset);
      offset += chunk.length;
    });
    return result;
  }

  function createZip(files) {
    var localChunks = [];
    var centralChunks = [];
    var offset = 0;
    var now = dosDateTime(new Date());
    files.forEach(function (file) {
      var name = toBytes(file.name);
      var data = toBytes(file.data);
      var crc = crc32(data);
      var local = [];
      pushU32(local, 0x04034B50);
      pushU16(local, 20);
      pushU16(local, ZIP_UTF8_FLAG);
      pushU16(local, 0);
      pushU16(local, now.time);
      pushU16(local, now.date);
      pushU32(local, crc);
      pushU32(local, data.length);
      pushU32(local, data.length);
      pushU16(local, name.length);
      pushU16(local, 0);
      var localHeader = new Uint8Array(local);
      localChunks.push(localHeader, name, data);

      var central = [];
      pushU32(central, 0x02014B50);
      pushU16(central, 20);
      pushU16(central, 20);
      pushU16(central, ZIP_UTF8_FLAG);
      pushU16(central, 0);
      pushU16(central, now.time);
      pushU16(central, now.date);
      pushU32(central, crc);
      pushU32(central, data.length);
      pushU32(central, data.length);
      pushU16(central, name.length);
      pushU16(central, 0);
      pushU16(central, 0);
      pushU16(central, 0);
      pushU16(central, 0);
      pushU32(central, 0);
      pushU32(central, offset);
      centralChunks.push(new Uint8Array(central), name);
      offset += localHeader.length + name.length + data.length;
    });

    var centralData = joinBytes(centralChunks);
    var end = [];
    pushU32(end, 0x06054B50);
    pushU16(end, 0);
    pushU16(end, 0);
    pushU16(end, files.length);
    pushU16(end, files.length);
    pushU32(end, centralData.length);
    pushU32(end, offset);
    pushU16(end, 0);
    return joinBytes(localChunks.concat([centralData, new Uint8Array(end)]));
  }

  var api = {
    buildDocx: buildDocx,
    parseInline: parseInline,
    parseMarkdown: parseMarkdown,
    renderPreviewHtml: renderPreviewHtml,
    sanitizeFilename: sanitizeFilename
  };

  root.MarkdownDocx = api;
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
}(typeof window !== "undefined" ? window : globalThis));
