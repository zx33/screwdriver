package main

import (
	"bytes"
	"embed"
	"encoding/base64"
	"fmt"
	"html"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"

	"modernc.org/quickjs"
)

//go:embed assets/katex/katex.min.css assets/katex/katex.min.js assets/katex/fonts/*.woff2
var katexAssets embed.FS

var fontURL = regexp.MustCompile(`url\(fonts/([\w-]+\.woff2)\)`)
var unusedFonts = regexp.MustCompile(`,url\(fonts/[^)]+\.(woff|ttf)\) format\("(woff|truetype)"\)`)

func renderHTML(source []byte, directory, title string) ([]byte, error) {
	css, err := katexAssets.ReadFile("assets/katex/katex.min.css")
	if err != nil {
		return nil, err
	}
	var fontErr error
	style := fontURL.ReplaceAllStringFunc(string(css), func(match string) string {
		name := fontURL.FindStringSubmatch(match)[1]
		data, readErr := katexAssets.ReadFile("assets/katex/fonts/" + name)
		if readErr != nil {
			fontErr = readErr
			return match
		}
		return "url(data:font/woff2;base64," + base64.StdEncoding.EncodeToString(data) + ")"
	})
	if fontErr != nil {
		return nil, fontErr
	}
	style = unusedFonts.ReplaceAllString(style, "")
	js, err := katexAssets.ReadFile("assets/katex/katex.min.js")
	if err != nil {
		return nil, err
	}
	vm, err := quickjs.NewVM()
	if err != nil {
		return nil, err
	}
	defer vm.Close()
	if _, err = vm.Eval(string(js), quickjs.EvalGlobal); err != nil {
		return nil, err
	}
	md := newMarkdown(&mathHTMLRenderer{vm: vm})
	var content bytes.Buffer
	if err = md.Convert(source, &content); err != nil {
		return nil, err
	}
	abs, err := filepath.Abs(directory)
	if err != nil {
		return nil, err
	}
	base := (&url.URL{Scheme: "file", Path: filepath.ToSlash(abs) + "/"}).String()
	page := `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title><base href="%s">
<style>%s
:root{color-scheme:light;--text:#243247;--muted:#64748b;--line:#dce4ed;--accent:#315bd6}
*{box-sizing:border-box}body{margin:0;background:#f4f6fa;color:var(--text);font:16px/1.8 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;overflow-wrap:break-word}
main{max-width:900px;margin:40px auto;padding:48px 64px;background:#fff;border:1px solid #e5eaf0;border-radius:16px;box-shadow:0 12px 45px #2432470d}
h1,h2,h3,h4,h5,h6{line-height:1.35;margin:1.6em 0 .6em;color:#17253a}h1{font-size:2em;margin-top:0;padding-bottom:.3em;border-bottom:1px solid var(--line)}h2{padding-bottom:.25em;border-bottom:1px solid var(--line)}
p,ul,ol,blockquote,pre,table{margin:1em 0}a{color:var(--accent)}img{max-width:100%%;height:auto;border-radius:6px}blockquote{margin-left:0;padding:.05em 1em;border-left:4px solid #a9bcf3;color:var(--muted);background:#f7f9ff}
code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.9em;background:#f0f3f8;padding:.15em .35em;border-radius:4px}pre{overflow:auto;padding:1em 1.2em;background:#17243a;color:#e7edf5;border-radius:8px;line-height:1.55}pre code{padding:0;background:transparent}
table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid var(--line);padding:.45em .7em}th{background:#f4f7fb}hr{border:0;border-top:1px solid var(--line)}.katex-display{overflow-x:auto;overflow-y:hidden;padding:.2em 0}
@media(max-width:640px){main{margin:0;padding:28px 20px;border:0;border-radius:0}}
</style></head><body><main>%s</main></body></html>`
	return []byte(fmt.Sprintf(page, html.EscapeString(title), html.EscapeString(base), style, content.String())), nil
}
func openPreview(source []byte, directory, title string) error {
	page, err := renderHTML(source, directory, title)
	if err != nil {
		return err
	}
	dir, err := os.MkdirTemp("", "mdcat-")
	if err != nil {
		return err
	}
	file := filepath.Join(dir, "preview.html")
	if err = os.WriteFile(file, page, 0600); err != nil {
		return err
	}
	opener := "xdg-open"
	if runtime.GOOS == "darwin" {
		opener = "open"
	}
	if err = exec.Command(opener, file).Run(); err != nil {
		return fmt.Errorf("无法启动 %s，可手动打开 %s", opener, file)
	}
	fmt.Println("已打开浏览器预览：" + file)
	return nil
}
