package main

import (
	"encoding/base64"
	"fmt"
	"html"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"

	katex "github.com/FurqanSoftware/goldmark-katex"
	"github.com/mattn/go-runewidth"
	"github.com/yuin/goldmark/ast"
	extast "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
)

type terminalOptions struct {
	color                    bool
	imageProtocol, directory string
	columns                  int
}
type terminalRenderer struct {
	source  []byte
	options terminalOptions
}

var ansiPattern = regexp.MustCompile(`\x1b\[[0-9;]*m`)
var styles = map[string][2]string{
	"bold": {"1", "22"}, "dim": {"2", "22"}, "italic": {"3", "23"}, "underline": {"4", "24"},
	"strike": {"9", "29"}, "blue": {"34", "39"}, "cyan": {"36", "39"}, "yellow": {"33", "39"}, "magenta": {"35", "39"},
}

func cleanTerminal(value string) string {
	value = strings.ReplaceAll(value, "\r\n", "\n")
	return strings.Map(func(r rune) rune {
		if r == '\r' {
			return '\n'
		}
		if r == '\n' || r == '\t' {
			return r
		}
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, value)
}
func textValue(value []byte) string {
	return cleanTerminal(html.UnescapeString(string(util.UnescapePunctuations(value))))
}
func displayWidth(s string) int { return runewidth.StringWidth(ansiPattern.ReplaceAllString(s, "")) }

func (r *terminalRenderer) paint(value, style string) string {
	if !r.options.color || value == "" {
		return value
	}
	codes := styles[style]
	open, close := "\x1b["+codes[0]+"m", "\x1b["+codes[1]+"m"
	return open + strings.ReplaceAll(value, close, close+open) + close
}

func renderTerminal(source []byte, options terminalOptions) string {
	r := &terminalRenderer{source: source, options: options}
	doc := newMarkdown(nil).Parser().Parse(text.NewReader(source))
	return strings.TrimRight(r.blocks(doc), "\n") + "\n"
}
func (r *terminalRenderer) blocks(parent ast.Node) string {
	var blocks []string
	for child := parent.FirstChild(); child != nil; child = child.NextSibling() {
		if block := r.block(child); block != "" {
			blocks = append(blocks, block)
		}
	}
	return strings.Join(blocks, "\n\n")
}
func (r *terminalRenderer) block(node ast.Node) string {
	switch n := node.(type) {
	case *ast.Heading:
		prefix, color := "━━ ", "blue"
		if n.Level > 1 {
			prefix, color = strings.Repeat("▸", min(n.Level-1, 3))+" ", "cyan"
		}
		return r.paint(r.paint(prefix+r.inlineChildren(n), "bold"), color)
	case *ast.Paragraph, *ast.TextBlock:
		content := r.inlineChildren(n)
		var images []ast.Node
		var collect func(ast.Node)
		collect = func(parent ast.Node) {
			for c := parent.FirstChild(); c != nil; c = c.NextSibling() {
				if _, ok := c.(*ast.Image); ok {
					images = append(images, c)
				} else {
					collect(c)
				}
			}
		}
		collect(n)
		for _, image := range images {
			if seq := r.imageSequence(image.(*ast.Image)); seq != "" {
				content += "\n" + strings.TrimSuffix(seq, "\n")
			}
		}
		return content
	case *ast.Blockquote:
		var lines []string
		for _, line := range strings.Split(r.blocks(n), "\n") {
			lines = append(lines, r.paint("│ ", "cyan")+line)
		}
		return strings.Join(lines, "\n")
	case *ast.List:
		var items []string
		index := n.Start
		for item := n.FirstChild(); item != nil; item = item.NextSibling() {
			marker := "• "
			if n.IsOrdered() {
				marker = fmt.Sprintf("%d. ", index)
				index++
			}
			content := strings.TrimSpace(r.blocks(item))
			items = append(items, r.paint(marker, "cyan")+strings.ReplaceAll(content, "\n", "\n"+strings.Repeat(" ", displayWidth(marker))))
		}
		return strings.Join(items, "\n")
	case *ast.FencedCodeBlock:
		return r.codeBlock(string(n.Language(r.source)), string(n.Lines().Value(r.source)))
	case *ast.CodeBlock:
		return r.codeBlock("", string(n.Lines().Value(r.source)))
	case *katex.Block:
		return r.paint("$$\n"+strings.TrimSpace(cleanTerminal(string(n.Equation(r.source))))+"\n$$", "magenta")
	case *extast.Table:
		return r.table(n)
	case *ast.ThematicBreak:
		return r.paint(strings.Repeat("─", max(1, min(r.options.columns, 60))), "dim")
	case *ast.HTMLBlock:
		return cleanTerminal(string(n.Lines().Value(r.source)))
	default:
		return r.blocks(node)
	}
}
func (r *terminalRenderer) codeBlock(language, code string) string {
	label := ""
	if language != "" {
		label = " " + cleanTerminal(language) + " "
	}
	header := r.paint("┌─"+label+strings.Repeat("─", max(3, 20-displayWidth(label))), "dim")
	code = strings.TrimSuffix(cleanTerminal(code), "\n")
	var lines []string
	for _, line := range strings.Split(code, "\n") {
		lines = append(lines, r.paint("│ ", "dim")+line)
	}
	return header + "\n" + strings.Join(lines, "\n") + "\n" + r.paint("└"+strings.Repeat("─", 20), "dim")
}
func (r *terminalRenderer) inlineChildren(parent ast.Node) string {
	var out strings.Builder
	for child := parent.FirstChild(); child != nil; child = child.NextSibling() {
		out.WriteString(r.inline(child))
	}
	return out.String()
}
func (r *terminalRenderer) inline(node ast.Node) string {
	switch n := node.(type) {
	case *ast.Text:
		value := n.Value(r.source)
		str := textValue(value)
		if n.IsRaw() {
			str = cleanTerminal(string(value))
		}
		if n.SoftLineBreak() || n.HardLineBreak() {
			str += "\n"
		}
		return str
	case *ast.String:
		return textValue(n.Value)
	case *ast.Emphasis:
		style := "italic"
		if n.Level == 2 {
			style = "bold"
		}
		return r.paint(r.inlineChildren(n), style)
	case *extast.Strikethrough:
		return r.paint(r.inlineChildren(n), "strike")
	case *ast.CodeSpan:
		return r.paint(strings.ReplaceAll(r.inlineChildren(n), "\n", " "), "yellow")
	case *katex.Inline:
		delim := "$"
		if n.Display {
			delim = "$$"
		}
		return r.paint(delim+cleanTerminal(string(n.Equation))+delim, "magenta")
	case *ast.Link:
		label, target := r.inlineChildren(n), textValue(n.Destination)
		if target != "" && ansiPattern.ReplaceAllString(label, "") != target {
			return r.paint(label, "underline") + r.paint(" ("+target+")", "dim")
		}
		return r.paint(label, "underline")
	case *ast.AutoLink:
		return r.paint(textValue(n.Label(r.source)), "underline")
	case *ast.Image:
		label := ansiPattern.ReplaceAllString(r.inlineChildren(n), "")
		if label == "" {
			label = "无描述"
		}
		return r.paint("[图片: "+label+"]", "cyan") + r.paint(" ("+textValue(n.Destination)+")", "dim")
	case *extast.TaskCheckBox:
		if n.IsChecked {
			return "☑ "
		}
		return "☐ "
	case *ast.RawHTML:
		var out strings.Builder
		for i := 0; i < n.Segments.Len(); i++ {
			seg := n.Segments.At(i)
			out.Write(seg.Value(r.source))
		}
		return cleanTerminal(out.String())
	default:
		return r.inlineChildren(node)
	}
}
func (r *terminalRenderer) table(node *extast.Table) string {
	var rows [][]string
	for row := node.FirstChild(); row != nil; row = row.NextSibling() {
		var cells []string
		for cell := row.FirstChild(); cell != nil; cell = cell.NextSibling() {
			cells = append(cells, strings.ReplaceAll(r.inlineChildren(cell), "\n", " "))
		}
		rows = append(rows, cells)
	}
	if len(rows) == 0 {
		return ""
	}
	widths := make([]int, len(node.Alignments))
	for i := range widths {
		widths[i] = 3
		for _, row := range rows {
			if i < len(row) {
				widths[i] = max(widths[i], displayWidth(row[i]))
			}
		}
	}
	line := func(row []string) string {
		var cells []string
		for i, w := range widths {
			value := ""
			if i < len(row) {
				value = row[i]
			}
			pad := max(0, w-displayWidth(value))
			switch node.Alignments[i] {
			case extast.AlignRight:
				value = strings.Repeat(" ", pad) + value
			case extast.AlignCenter:
				value = strings.Repeat(" ", pad/2) + value + strings.Repeat(" ", pad-pad/2)
			default:
				value += strings.Repeat(" ", pad)
			}
			cells = append(cells, value)
		}
		return "| " + strings.Join(cells, " | ") + " |"
	}
	var dashes []string
	for _, w := range widths {
		dashes = append(dashes, strings.Repeat("─", w))
	}
	out := []string{r.paint(line(rows[0]), "bold"), r.paint("|-"+strings.Join(dashes, "-|-")+"-|", "dim")}
	for _, row := range rows[1:] {
		out = append(out, line(row))
	}
	return strings.Join(out, "\n")
}
func (r *terminalRenderer) imageSequence(image *ast.Image) string {
	protocol := r.options.imageProtocol
	if protocol == "" {
		return ""
	}
	value := html.UnescapeString(string(image.Destination))
	u, err := url.Parse(value)
	if err != nil || (u.Scheme != "" && u.Scheme != "file") || (u.Scheme == "file" && u.Host != "" && u.Host != "localhost") || (u.Scheme == "" && u.Host != "") {
		return ""
	}
	file := filepath.FromSlash(u.Path)
	if !filepath.IsAbs(file) {
		file = filepath.Join(r.options.directory, file)
	}
	info, err := os.Stat(file)
	if err != nil || !info.Mode().IsRegular() || info.Size() > 20*1024*1024 {
		return ""
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return ""
	}
	encoded := base64.StdEncoding.EncodeToString(data)
	if protocol == "iterm" {
		ext := strings.ToLower(filepath.Ext(file))
		if ext != ".png" && ext != ".jpg" && ext != ".jpeg" && ext != ".gif" {
			return ""
		}
		name := base64.StdEncoding.EncodeToString([]byte(filepath.Base(file)))
		return "\x1b]1337;File=name=" + name + ";width=80%;height=20;preserveAspectRatio=1;inline=1:" + encoded + "\x07\n"
	}
	if protocol == "kitty" && strings.HasPrefix(string(data), "\x89PNG\r\n\x1a\n") {
		var result strings.Builder
		for offset := 0; offset < len(encoded); offset += 4096 {
			end := min(offset+4096, len(encoded))
			more := 0
			if end < len(encoded) {
				more = 1
			}
			params := fmt.Sprintf("m=%d", more)
			if offset == 0 {
				params = fmt.Sprintf("a=T,f=100,m=%d", more)
			}
			result.WriteString("\x1b_G" + params + ";" + encoded[offset:end] + "\x1b\\")
		}
		return result.String() + "\n"
	}
	return ""
}
