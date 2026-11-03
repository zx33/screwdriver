#!/usr/bin/env bash
set -eu

tool_dir=$(CDPATH= cd -P -- "$(dirname -- "$0")/.." && pwd)

if ! command -v go >/dev/null 2>&1; then
  printf '%s\n' '构建 mdcat 需要 Go 1.27.3 或更新版本。' >&2
  exit 1
fi

target=${1:-}
if [ -z "$target" ]; then
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64) target=macos-arm64 ;;
    Darwin:x86_64) target=macos-x64 ;;
    Linux:aarch64|Linux:arm64) target=linux-arm64 ;;
    Linux:x86_64) target=linux-x64 ;;
    *) printf '%s\n' '无法识别当前系统和架构，请手动指定构建目标。' >&2; exit 1 ;;
  esac
fi

case "$target" in
  macos-arm64) target_os=darwin; target_arch=arm64 ;;
  macos-x64) target_os=darwin; target_arch=amd64 ;;
  linux-arm64) target_os=linux; target_arch=arm64 ;;
  linux-x64) target_os=linux; target_arch=amd64 ;;
  *) printf '未知目标: %s\n可选: macos-arm64 macos-x64 linux-arm64 linux-x64\n' "$target" >&2; exit 1 ;;
esac

mkdir -p "$tool_dir/dist"
output="$tool_dir/dist/mdcat-$target"
cd "$tool_dir"
CGO_ENABLED=0 GOOS="$target_os" GOARCH="$target_arch" go build -trimpath -ldflags='-s -w' -o "$output.tmp" .
mv -f "$output.tmp" "$output"
printf '独立可执行文件：%s\n' "$output"
