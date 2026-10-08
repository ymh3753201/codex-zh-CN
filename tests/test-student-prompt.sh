#!/bin/bash

set -eu

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PROMPT="$PROJECT_ROOT/docs/学员通用AI下载与汉化提示词.md"

fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
require_text() { LC_ALL=C grep -F -q -- "$2" "$1" || fail "$3"; }

[ -f "$PROMPT" ] || fail "缺少学员通用提示词"
require_text "$PROMPT" 'https://github.com/ymh3753201/codex-zh-CN' "提示词缺少官方仓库地址"
SNAPSHOT="$PROJECT_ROOT/resources/download-snapshot.json"
COMMIT="$(/usr/bin/plutil -extract commit raw -o - "$SNAPSHOT")"
URL="$(/usr/bin/plutil -extract url raw -o - "$SNAPSHOT")"
HASH="$(/usr/bin/plutil -extract archiveSha256 raw -o - "$SNAPSHOT")"
require_text "$PROMPT" "$COMMIT" "提示词缺少固定源码快照"
require_text "$PROMPT" "$URL" "提示词缺少直接下载地址"
require_text "$PROMPT" "$HASH" "提示词缺少对应 ZIP 校验值"
require_text "$PROMPT" '不要改用 main' "提示词没有阻止旧主分支回退"
require_text "$PROMPT" 'check-macos-package.sh' "提示词缺少工具包预检"
require_text "$PROMPT" 'scripts\install_windows.ps1' "提示词缺少 Windows 安装入口"
require_text "$PROMPT" 'scripts/install_macos.sh' "提示词缺少 macOS 安装入口"
require_text "$PROMPT" '-NoRestart' "提示词缺少 Windows 不重启保护"
require_text "$PROMPT" '--no-restart' "提示词缺少 macOS 不重启保护"
require_text "$PROMPT" 'resourcesReady' "提示词没有区分中文资源状态"
require_text "$PROMPT" 'installationReady' "提示词没有区分安装准备状态"
require_text "$PROMPT" '界面中文已确认' "提示词没有保留人工界面验收"
require_text "$PROMPT" '助教反馈正文' "提示词缺少助教反馈格式"

printf '[PASS] Windows/macOS 通用学员提示词关键步骤完整\n'
