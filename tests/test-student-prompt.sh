#!/bin/bash

set -eu

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PROMPT="$PROJECT_ROOT/docs/学员通用AI下载与汉化提示词.md"
README="$PROJECT_ROOT/README.md"

fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
require_text() { LC_ALL=C grep -F -q -- "$2" "$1" || fail "$3"; }

[ -f "$PROMPT" ] || fail "缺少学员通用提示词"
require_text "$PROMPT" 'https://github.com/ymh3753201/codex-zh-CN' "提示词缺少官方仓库地址"
require_text "$PROMPT" '372bb3a5651730ac37cc7cf356e8c579dd587014' "提示词缺少已验证的固定提交"
require_text "$PROMPT" 'scripts\install_windows.ps1' "提示词缺少 Windows 安装入口"
require_text "$PROMPT" 'scripts/install_macos.sh' "提示词缺少 macOS 安装入口"
require_text "$PROMPT" '-NoRestart' "提示词缺少 Windows 不重启保护"
require_text "$PROMPT" '--no-restart' "提示词缺少 macOS 不重启保护"
require_text "$PROMPT" 'resourcesReady' "提示词没有区分中文资源状态"
require_text "$PROMPT" 'installationReady' "提示词没有区分安装准备状态"
require_text "$PROMPT" '界面中文已确认' "提示词没有保留人工界面验收"
require_text "$PROMPT" '助教反馈正文' "提示词缺少助教反馈格式"
require_text "$README" '学员通用 AI 下载与汉化提示词' "README 缺少提示词入口"

printf '[PASS] Windows/macOS 通用学员提示词关键步骤完整\n'
