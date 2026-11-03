package main

import (
	"encoding/base64"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTerminalMarkdown(t *testing.T) {
	source := []byte("# 中文标题\n\n**粗体**、*斜体*、[链接](https://example.com)。\n\n- [x] 完成\n- [ ] 等待\n\n| 项目 | 数值 |\n| --- | ---: |\n| 甲 | 12 |\n\n```js\nconst x = \"**原文**\";\n```\n\n\x1b]危险")
	out := renderTerminal(source, terminalOptions{color: true, columns: 80})
	for _, wanted := range []string{"━━ 中文标题", "\x1b[1m粗体\x1b[22m", "https://example.com", "☑ 完成", "☐ 等待", "项目", "数值", `const x = "**原文**"`} {
		if !strings.Contains(out, wanted) {
			t.Errorf("terminal output missing %q:\n%s", wanted, out)
		}
	}
	if strings.Contains(out, "\x1b]") {
		t.Error("document supplied a terminal control sequence")
	}
}

func TestPreviewMathImagesAndOfflineFonts(t *testing.T) {
	dir := t.TempDir()
	source := []byte("行内 $E=mc^2$ 和 \\(a+b\\)。\n\n$$\n\\frac{a}{b}\n$$\n\n\\[\nx^2\n\\]\n\n`$code$`\n\n![图](图片%20one.png)\n")
	page, err := renderHTML(source, dir, "预览")
	if err != nil {
		t.Fatal(err)
	}
	html := string(page)
	if count := strings.Count(html, `class="katex"`); count != 4 {
		t.Fatalf("got %d rendered formulas", count)
	}
	base := (&url.URL{Scheme: "file", Path: filepath.ToSlash(dir) + "/"}).String()
	for _, wanted := range []string{"<mfrac>", "<code>$code$</code>", "data:font/woff2;base64,", `<base href="` + base + `">`, `src="%E5%9B%BE%E7%89%87%20one.png"`} {
		if !strings.Contains(html, wanted) {
			t.Errorf("preview missing %q", wanted)
		}
	}
	if strings.Contains(html, "url(fonts/") {
		t.Error("preview still depends on external font files")
	}
}

func TestInlineMathDoesNotRenderInsideCode(t *testing.T) {
	source := []byte("`\\(not math\\)`\n\n```tex\n\\[not math\\]\n```\n\n$actual$\n")
	page, err := renderHTML(source, t.TempDir(), "test")
	if err != nil {
		t.Fatal(err)
	}
	if count := strings.Count(string(page), `class="katex"`); count != 1 {
		t.Fatalf("got %d rendered formulas, want 1", count)
	}
}

func TestTerminalImagesAndFallback(t *testing.T) {
	dir := t.TempDir()
	data, err := base64.StdEncoding.DecodeString("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X8p8AAAAASUVORK5CYII=")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(dir, "图片 one.png"), data, 0600); err != nil {
		t.Fatal(err)
	}
	source := []byte("[![图片](图片%20one.png)](https://example.com)\n")
	iterm := renderTerminal(source, terminalOptions{directory: dir, imageProtocol: "iterm", columns: 80})
	kitty := renderTerminal(source, terminalOptions{directory: dir, imageProtocol: "kitty", columns: 80})
	plain := renderTerminal(source, terminalOptions{directory: dir, columns: 80})
	if !strings.Contains(iterm, "\x1b]1337;File=") || !strings.Contains(iterm, base64.StdEncoding.EncodeToString(data)) {
		t.Error("missing iTerm image")
	}
	if !strings.Contains(kitty, "\x1b_Ga=T,f=100,m=0;") {
		t.Error("missing Kitty image")
	}
	if !strings.Contains(plain, "[图片: 图片]") || strings.Contains(plain, "\x1b") {
		t.Error("plain output did not retain image reference")
	}
	missing := renderTerminal([]byte("![missing](absent.png)"), terminalOptions{directory: dir, imageProtocol: "iterm", columns: 80})
	if strings.Contains(missing, "\x1b]") {
		t.Error("unexpected image for missing file")
	}
}
