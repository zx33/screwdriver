package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/term"
)

const usage = `用法: mdcat [选项] [文件|-]

在终端阅读 Markdown；省略文件时从管道读取。

  --browser     在浏览器中预览图片与排版后的公式
  --color       强制输出终端颜色，例如配合 less -R
  --no-color    不输出终端颜色
  --no-images   不在终端显示图片
  -h, --help    显示帮助

示例:
  mdcat README.md
  cat README.md | mdcat
  mdcat --color README.md | less -R
  mdcat --browser README.md`

type options struct {
	browser, color, showImages bool
	file                       string
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "mdcat:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	_, noColor := os.LookupEnv("NO_COLOR")
	tty := term.IsTerminal(int(os.Stdout.Fd()))
	opt := options{color: tty && os.Getenv("TERM") != "dumb" && !noColor, showImages: true}
	optionsEnded, hasFile := false, false
	for _, arg := range args {
		switch {
		case !optionsEnded && arg == "--":
			optionsEnded = true
		case !optionsEnded && (arg == "--help" || arg == "-h"):
			fmt.Println(usage)
			return nil
		case !optionsEnded && arg == "--browser":
			opt.browser = true
		case !optionsEnded && arg == "--color":
			opt.color = true
		case !optionsEnded && arg == "--no-color":
			opt.color = false
		case !optionsEnded && arg == "--no-images":
			opt.showImages = false
		case !optionsEnded && strings.HasPrefix(arg, "-") && arg != "-":
			return fmt.Errorf("未知选项: %s", arg)
		case hasFile:
			return fmt.Errorf("一次只能打开一个文件")
		default:
			opt.file, hasFile = arg, true
		}
	}
	if !hasFile && term.IsTerminal(int(os.Stdin.Fd())) {
		fmt.Println(usage)
		return nil
	}
	var source []byte
	var err error
	dir, err := os.Getwd()
	if err != nil {
		return err
	}
	title := "Markdown 预览"
	if !hasFile || opt.file == "-" {
		source, err = io.ReadAll(os.Stdin)
	} else {
		file, pathErr := filepath.Abs(opt.file)
		if pathErr != nil {
			return pathErr
		}
		source, err = os.ReadFile(file)
		dir, title = filepath.Dir(file), filepath.Base(file)
	}
	if err != nil {
		return err
	}
	source = []byte(strings.TrimPrefix(string(source), "\ufeff"))
	if opt.browser {
		return openPreview(source, dir, title)
	}
	protocol := ""
	if tty && opt.showImages && os.Getenv("TMUX") == "" && os.Getenv("STY") == "" {
		switch {
		case os.Getenv("TERM_PROGRAM") == "iTerm.app" || os.Getenv("TERM_PROGRAM") == "WezTerm":
			protocol = "iterm"
		case os.Getenv("KITTY_WINDOW_ID") != "" || os.Getenv("TERM") == "xterm-kitty":
			protocol = "kitty"
		}
	}
	columns := 80
	if tty {
		if w, _, sizeErr := term.GetSize(int(os.Stdout.Fd())); sizeErr == nil {
			columns = w
		}
	}
	out := renderTerminal(source, terminalOptions{color: opt.color, imageProtocol: protocol, directory: dir, columns: columns})
	_, err = io.WriteString(os.Stdout, out)
	return err
}
