package main

import (
	"bytes"
	"encoding/json"
	"fmt"

	katex "github.com/FurqanSoftware/goldmark-katex"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
	"modernc.org/quickjs"
)

// bracketInline parses the LaTeX \\(...\\) form alongside dollar math.
type bracketInline struct{}

func (bracketInline) Trigger() []byte { return []byte{'\\'} }
func (bracketInline) Parse(_ ast.Node, reader text.Reader, _ parser.Context) ast.Node {
	line, _ := reader.PeekLine()
	if !bytes.HasPrefix(line, []byte(`\(`)) {
		return nil
	}
	for i := 2; i+1 < len(line); i++ {
		if line[i] != '\\' {
			continue
		}
		if line[i+1] == ')' {
			if i == 2 {
				return nil
			}
			reader.Advance(i + 2)
			return &katex.Inline{Equation: append([]byte(nil), line[2:i]...)}
		}
		i++
	}
	return nil
}

// bracketBlock keeps \\[...\\] equations intact before Markdown block parsing.
type bracketBlock struct{}

func (bracketBlock) Trigger() []byte { return []byte{'\\'} }
func (bracketBlock) Open(_ ast.Node, reader text.Reader, _ parser.Context) (ast.Node, parser.State) {
	line, segment := reader.PeekLine()
	indent := util.TrimLeftSpaceLength(line)
	if !bytes.HasPrefix(line[indent:], []byte(`\[`)) {
		return nil, parser.NoChildren
	}
	start, rest := segment.Start+indent+2, line[indent+2:]
	node := &katex.Block{}
	if end := bytes.Index(rest, []byte(`\]`)); end >= 0 {
		if !util.IsBlank(rest[end+2:]) || util.IsBlank(rest[:end]) {
			return nil, parser.NoChildren
		}
		node.Lines().Append(text.NewSegment(start, start+end))
		node.SetAttributeString("mdcat-closed", true)
		reader.AdvanceToEOL()
		return node, parser.NoChildren
	}
	if !util.IsBlank(rest) {
		node.Lines().Append(text.NewSegment(start, segment.Stop))
	}
	reader.AdvanceToEOL()
	return node, parser.NoChildren
}
func (bracketBlock) Continue(node ast.Node, reader text.Reader, _ parser.Context) parser.State {
	if _, closed := node.AttributeString("mdcat-closed"); closed {
		return parser.Close
	}
	line, segment := reader.PeekLine()
	end := bytes.Index(line, []byte(`\]`))
	if end < 0 {
		node.Lines().Append(segment)
		reader.AdvanceToEOL()
		return parser.Continue | parser.NoChildren
	}
	if !util.IsBlank(line[:end]) {
		node.Lines().Append(text.NewSegment(segment.Start, segment.Start+end))
	}
	reader.Advance(end + 2)
	if util.IsBlank(line[end+2:]) {
		reader.AdvanceToEOL()
	}
	return parser.Close
}
func (bracketBlock) Close(node ast.Node, _ text.Reader, _ parser.Context) {
	if node.Lines().Len() == 0 && node.Parent() != nil {
		node.Parent().RemoveChild(node.Parent(), node)
	}
}
func (bracketBlock) CanInterruptParagraph() bool { return true }
func (bracketBlock) CanAcceptIndentedLine() bool { return false }

func newMarkdown(mathRenderer *mathHTMLRenderer) goldmark.Markdown {
	options := []goldmark.Option{
		goldmark.WithExtensions(extension.GFM),
		goldmark.WithParserOptions(
			parser.WithBlockParsers(util.Prioritized(&katex.BlockParser{}, 50), util.Prioritized(bracketBlock{}, 49)),
			parser.WithInlineParsers(util.Prioritized(&katex.Parser{}, 0), util.Prioritized(bracketInline{}, 0)),
		),
	}
	if mathRenderer != nil {
		options = append(options, goldmark.WithRendererOptions(renderer.WithNodeRenderers(util.Prioritized(mathRenderer, 0))))
	}
	return goldmark.New(options...)
}

type mathHTMLRenderer struct{ vm *quickjs.VM }

func (r *mathHTMLRenderer) RegisterFuncs(reg renderer.NodeRendererFuncRegisterer) {
	reg.Register(katex.KindInline, r.inline)
	reg.Register(katex.KindBlock, r.block)
}
func (r *mathHTMLRenderer) inline(w util.BufWriter, _ []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if !entering {
		return ast.WalkContinue, nil
	}
	math := node.(*katex.Inline)
	return r.write(w, math.Equation, math.Display)
}
func (r *mathHTMLRenderer) block(w util.BufWriter, source []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if !entering {
		return ast.WalkContinue, nil
	}
	return r.write(w, node.(*katex.Block).Equation(source), true)
}
func (r *mathHTMLRenderer) write(w util.BufWriter, equation []byte, display bool) (ast.WalkStatus, error) {
	value, _ := json.Marshal(string(equation))
	expr := fmt.Sprintf("katex.renderToString(%s,{displayMode:%t,throwOnError:false})", value, display)
	result, err := r.vm.Eval(expr, quickjs.EvalGlobal)
	if err != nil {
		return ast.WalkStop, err
	}
	html, ok := result.(string)
	if !ok {
		return ast.WalkStop, fmt.Errorf("无法渲染公式")
	}
	_, err = w.WriteString(html)
	return ast.WalkContinue, err
}
