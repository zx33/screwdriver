(function (root) {
  "use strict";

  var wordSegmenter = null;
  if (typeof Intl !== "undefined" && Intl.Segmenter) {
    try {
      wordSegmenter = new Intl.Segmenter(undefined, { granularity: "word" });
    } catch (error) {
      wordSegmenter = null;
    }
  }

  function normalizeText(value) {
    return String(value || "").replace(/\r\n?/g, "\n");
  }

  function splitLines(value) {
    var normalized = normalizeText(value);
    return normalized === "" ? [] : normalized.split("\n");
  }

  function fallbackWordTokens(value) {
    var matches = String(value).match(/[\u3400-\u9fff]|[\p{L}\p{N}_]+|[^\p{L}\p{N}\s_]+|\s+/gu);
    return matches || [];
  }

  function tokenize(value, granularity) {
    var text = String(value || "");
    if (granularity === "char") {
      return Array.from(text);
    }
    if (wordSegmenter) {
      return Array.from(wordSegmenter.segment(text), function (part) {
        return part.segment;
      });
    }
    return fallbackWordTokens(text);
  }

  function isCountableToken(token, granularity) {
    if (/^\s+$/u.test(token)) {
      return false;
    }
    if (granularity === "char") {
      return true;
    }
    return /[\p{L}\p{N}\u3400-\u9fff]/u.test(token);
  }

  function countTokens(value, granularity) {
    return tokenize(value, granularity).filter(function (token) {
      return isCountableToken(token, granularity);
    }).length;
  }

  function myersDiff(a, b, equals) {
    var left = a || [];
    var right = b || [];
    var same = equals || function (x, y) { return x === y; };
    var n = left.length;
    var m = right.length;

    if (n === 0) {
      return right.map(function (value) { return { type: "insert", b: value }; });
    }
    if (m === 0) {
      return left.map(function (value) { return { type: "delete", a: value }; });
    }

    var max = n + m;
    var frontier = new Map([[1, 0]]);
    var trace = [];
    var finalDepth = 0;

    outer:
    for (var depth = 0; depth <= max; depth += 1) {
      trace.push(new Map(frontier));
      for (var diagonal = -depth; diagonal <= depth; diagonal += 2) {
        var x;
        var down = frontier.get(diagonal + 1);
        var rightward = frontier.get(diagonal - 1);
        if (diagonal === -depth || (diagonal !== depth && (down || 0) > (rightward || 0))) {
          x = down || 0;
        } else {
          x = (rightward || 0) + 1;
        }

        var y = x - diagonal;
        while (x < n && y < m && same(left[x], right[y])) {
          x += 1;
          y += 1;
        }
        frontier.set(diagonal, x);

        if (x >= n && y >= m) {
          finalDepth = depth;
          break outer;
        }
      }
    }

    var operations = [];
    var currentX = n;
    var currentY = m;

    for (var currentDepth = finalDepth; currentDepth > 0; currentDepth -= 1) {
      var previousFrontier = trace[currentDepth];
      var currentDiagonal = currentX - currentY;
      var previousDiagonal;
      var downValue = previousFrontier.get(currentDiagonal + 1);
      var rightValue = previousFrontier.get(currentDiagonal - 1);

      if (currentDiagonal === -currentDepth || (currentDiagonal !== currentDepth && (downValue || 0) > (rightValue || 0))) {
        previousDiagonal = currentDiagonal + 1;
      } else {
        previousDiagonal = currentDiagonal - 1;
      }

      var previousX = previousFrontier.get(previousDiagonal) || 0;
      var previousY = previousX - previousDiagonal;

      while (currentX > previousX && currentY > previousY) {
        operations.push({ type: "equal", a: left[currentX - 1], b: right[currentY - 1] });
        currentX -= 1;
        currentY -= 1;
      }

      if (currentX === previousX) {
        operations.push({ type: "insert", b: right[currentY - 1] });
        currentY -= 1;
      } else {
        operations.push({ type: "delete", a: left[currentX - 1] });
        currentX -= 1;
      }
    }

    while (currentX > 0 && currentY > 0) {
      operations.push({ type: "equal", a: left[currentX - 1], b: right[currentY - 1] });
      currentX -= 1;
      currentY -= 1;
    }
    while (currentX > 0) {
      operations.push({ type: "delete", a: left[currentX - 1] });
      currentX -= 1;
    }
    while (currentY > 0) {
      operations.push({ type: "insert", b: right[currentY - 1] });
      currentY -= 1;
    }

    operations.reverse();
    return mergeOperations(operations);
  }

  function mergeOperations(operations) {
    return operations.reduce(function (merged, operation) {
      var previous = merged[merged.length - 1];
      if (previous && previous.type === operation.type) {
        if (operation.type === "equal") {
          previous.aValues.push(operation.a);
          previous.bValues.push(operation.b);
        } else if (operation.type === "delete") {
          previous.aValues.push(operation.a);
        } else {
          previous.bValues.push(operation.b);
        }
        return merged;
      }

      var entry = { type: operation.type, aValues: [], bValues: [] };
      if (operation.type === "equal") {
        entry.aValues.push(operation.a);
        entry.bValues.push(operation.b);
      } else if (operation.type === "delete") {
        entry.aValues.push(operation.a);
      } else {
        entry.bValues.push(operation.b);
      }
      merged.push(entry);
      return merged;
    }, []).map(function (operation) {
      return {
        type: operation.type,
        a: operation.aValues.length === 1 ? operation.aValues[0] : operation.aValues,
        b: operation.bValues.length === 1 ? operation.bValues[0] : operation.bValues
      };
    });
  }

  function toArray(value) {
    if (Array.isArray(value)) {
      return value;
    }
    return value === undefined ? [] : [value];
  }

  function pairLineChanges(lineOperations) {
    var paired = [];
    var index = 0;

    while (index < lineOperations.length) {
      var operation = lineOperations[index];
      if (operation.type === "equal") {
        toArray(operation.a).forEach(function (line, offset) {
          paired.push({ kind: "equal", oldLine: line, newLine: toArray(operation.b)[offset] });
        });
        index += 1;
        continue;
      }

      var deleted = [];
      var inserted = [];
      while (index < lineOperations.length && lineOperations[index].type === "delete") {
        deleted = deleted.concat(toArray(lineOperations[index].a));
        index += 1;
      }
      while (index < lineOperations.length && lineOperations[index].type === "insert") {
        inserted = inserted.concat(toArray(lineOperations[index].b));
        index += 1;
      }

      var pairedCount = Math.min(deleted.length, inserted.length);
      for (var pairIndex = 0; pairIndex < pairedCount; pairIndex += 1) {
        paired.push({ kind: "replace", oldLine: deleted[pairIndex], newLine: inserted[pairIndex] });
      }
      for (var deletedIndex = pairedCount; deletedIndex < deleted.length; deletedIndex += 1) {
        paired.push({ kind: "delete", oldLine: deleted[deletedIndex], newLine: null });
      }
      for (var insertedIndex = pairedCount; insertedIndex < inserted.length; insertedIndex += 1) {
        paired.push({ kind: "insert", oldLine: null, newLine: inserted[insertedIndex] });
      }
    }

    return paired;
  }

  function countChangedGroups(lineOperations) {
    var groups = 0;
    var inGroup = false;
    lineOperations.forEach(function (operation) {
      if (operation.type === "equal") {
        inGroup = false;
      } else if (!inGroup) {
        groups += 1;
        inGroup = true;
      }
    });
    return groups;
  }

  function countChangedTokens(oldText, newText, granularity) {
    var tokenOperations = myersDiff(tokenize(oldText, granularity), tokenize(newText, granularity));
    return tokenOperations.reduce(function (counts, operation) {
      if (operation.type === "delete") {
        counts.removed += toArray(operation.a).filter(function (token) { return isCountableToken(token, granularity); }).length;
      } else if (operation.type === "insert") {
        counts.added += toArray(operation.b).filter(function (token) { return isCountableToken(token, granularity); }).length;
      }
      return counts;
    }, { added: 0, removed: 0 });
  }

  function buildDiff(oldText, newText, granularity) {
    var oldLines = splitLines(oldText);
    var newLines = splitLines(newText);
    var lineOperations = myersDiff(oldLines, newLines);
    var rows = pairLineChanges(lineOperations);
    var counts = { added: 0, removed: 0 };

    rows.forEach(function (row) {
      if (row.kind === "replace") {
        var replacement = countChangedTokens(row.oldLine, row.newLine, granularity);
        counts.added += replacement.added;
        counts.removed += replacement.removed;
      } else if (row.kind === "delete") {
        counts.removed += countTokens(row.oldLine, granularity);
      } else if (row.kind === "insert") {
        counts.added += countTokens(row.newLine, granularity);
      }
    });

    return {
      oldLines: oldLines,
      newLines: newLines,
      lineOperations: lineOperations,
      rows: rows,
      stats: {
        added: counts.added,
        removed: counts.removed,
        addedLines: rows.filter(function (row) { return row.kind === "insert" || row.kind === "replace"; }).reduce(function (sum, row) { return sum + (row.newLine === null ? 0 : 1); }, 0),
        removedLines: rows.filter(function (row) { return row.kind === "delete" || row.kind === "replace"; }).reduce(function (sum, row) { return sum + (row.oldLine === null ? 0 : 1); }, 0),
        changedLines: rows.filter(function (row) { return row.kind !== "equal"; }).length,
        groups: countChangedGroups(lineOperations),
        oldLineCount: oldLines.length,
        newLineCount: newLines.length
      }
    };
  }

  root.MarkdownDiff = {
    buildDiff: buildDiff,
    countChangedTokens: countChangedTokens,
    diffTokens: function (oldText, newText, granularity) {
      return myersDiff(tokenize(oldText, granularity), tokenize(newText, granularity));
    },
    tokenize: tokenize,
    normalizeText: normalizeText
  };
}(typeof window !== "undefined" ? window : globalThis));
