#!/bin/bash

set -eu

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUTPUT_DIR="$(mktemp -d /tmp/codex-zh-macos-release.XXXXXX)"
EXTRACT_DIR="$(mktemp -d /tmp/codex-zh-macos-extract.XXXXXX)"

cleanup() {
    case "$OUTPUT_DIR" in /tmp/codex-zh-macos-release.*) rm -rf -- "$OUTPUT_DIR" ;; esac
    case "$EXTRACT_DIR" in /tmp/codex-zh-macos-extract.*) rm -rf -- "$EXTRACT_DIR" ;; esac
}
trap cleanup EXIT HUP INT TERM

fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
VERSION="$(/usr/bin/plutil -extract release raw -o - "$PROJECT_ROOT/resources/macos-release.json")"
BASE="codex-zh-CN-macOS-v$VERSION"

/bin/bash "$PROJECT_ROOT/scripts/package-macos.sh" "$OUTPUT_DIR" >/dev/null
ZIP_PATH="$OUTPUT_DIR/$BASE.zip"
SHA_PATH="$OUTPUT_DIR/$BASE.sha256"
[ -f "$ZIP_PATH" ] || fail "工具包未生成"
[ -f "$SHA_PATH" ] || fail "SHA-256 文件未生成"
(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 -c "$(basename "$SHA_PATH")" >/dev/null
) || fail "SHA-256 校验失败"
GENERATED_HASH="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
RECORDED_HASH="$(grep -E '^[0-9a-f]{64}  codex-zh-CN-macOS-v' "$PROJECT_ROOT/docs/macOS工具包SHA256.md" | awk '{print $1}')"
[ "$GENERATED_HASH" = "$RECORDED_HASH" ] || fail "文档记录的工具包 SHA-256 已过期"

/usr/bin/ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
PACKAGE_ROOT="$EXTRACT_DIR/$BASE"
for relative in \
    'macOS-一键安装.command' \
    'macOS-检查状态.command' \
    'macOS-打开中文版.command' \
    'macOS-恢复英文.command' \
    'scripts/install_macos.sh' \
    'resources/macos-release.json' \
    'docs/macOS零基础安装教程.md' \
    'LICENSE'; do
    [ -f "$PACKAGE_ROOT/$relative" ] || fail "工具包缺少 $relative"
    [ "$(shasum -a 256 "$PACKAGE_ROOT/$relative" | awk '{print $1}')" = "$(shasum -a 256 "$PROJECT_ROOT/$relative" | awk '{print $1}')" ] || fail "工具包与源码不一致：$relative"
done

[ -x "$PACKAGE_ROOT/macOS-一键安装.command" ] || fail "双击入口没有执行权限"
[ -x "$PACKAGE_ROOT/scripts/install_macos.sh" ] || fail "安装脚本没有执行权限"
[ -z "$(find "$PACKAGE_ROOT" -name '.DS_Store' -print -quit)" ] || fail "工具包包含 .DS_Store"
/bin/bash -n "$PACKAGE_ROOT/scripts/install_macos.sh"
/bin/bash "$PACKAGE_ROOT/scripts/install_macos.sh" --help >/dev/null

printf '[PASS] macOS 发布包、源码哈希、执行权限和 SHA-256 校验通过\n'
