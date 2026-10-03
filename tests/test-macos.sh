#!/bin/bash

set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALLER="$PROJECT_ROOT/scripts/install_macos.sh"
TEST_ROOT="$(mktemp -d /tmp/codex-zh-macos-tests.XXXXXX)"
CASE_ROOT="$TEST_ROOT/中文 & (空格)"
PASS_COUNT=0

cleanup() {
    case "$TEST_ROOT" in /tmp/codex-zh-macos-tests.*) rm -rf -- "$TEST_ROOT" ;; esac
}
trap cleanup EXIT HUP INT TERM
mkdir -p -- "$CASE_ROOT"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3（实际：$1；期望：$2）"; }
assert_file() { [ -f "$1" ] || fail "$2：$1"; }
assert_not_file() { [ ! -f "$1" ] || fail "$2：$1"; }
assert_contains() { LC_ALL=C grep -F -q "$2" "$1" || fail "$3"; }
json_value() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
latest_report() { find "$1/zh-cn-tool/macos/diagnostics" -type f -name 'report-*.json' -print | LC_ALL=C sort | tail -n 1; }

create_app() {
    app="$1"; version="$2"; mode="${3:-complete}"; marker="${4:-v1}"
    mkdir -p -- "$app/Contents/MacOS" "$app/Contents/Resources"
    /bin/cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.openai.codex</string>
<key>CFBundleExecutable</key><string>ChatGPT</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>100</string>
</dict></plist>
EOF
    printf '#!/bin/bash\nexit 0\n' > "$app/Contents/MacOS/ChatGPT"
    chmod +x "$app/Contents/MacOS/ChatGPT"
    node "$PROJECT_ROOT/tests/make-macos-fixture.mjs" "$app/Contents/Resources/app.asar" "$mode" "$marker"
}

tree_hash() {
    find "$1" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
        shasum -a 256 "$file"
    done | shasum -a 256 | awk '{print $1}'
}

run_tool() {
    app="$1"; home="$2"; shift 2
    CODEX_ZH_TESTING=1 \
    CODEX_ZH_TEST_ARCH="${CODEX_ZH_TEST_ARCH_VALUE:-$(uname -m)}" \
    CODEX_ZH_TEST_MACHINE_ARCH="${CODEX_ZH_TEST_MACHINE_VALUE:-$(uname -m)}" \
    /bin/bash "$INSTALLER" --app "$app" --codex-home "$home" "$@"
}

APP="$CASE_ROOT/ChatGPT 学员版.app"
HOME_ONE="$CASE_ROOT/学员数据一"
create_app "$APP" "26.930.31730" complete v1
OFFICIAL_HASH="$(tree_hash "$APP")"

# 1. 首次安装：创建配置和有效状态，不启动/退出程序。
run_tool "$APP" "$HOME_ONE" --action install --no-restart >/dev/null || fail "首次安装失败"
assert_file "$HOME_ONE/config.toml" "首次安装没有生成配置"
assert_contains "$HOME_ONE/config.toml" 'localeOverride = "zh-CN"' "首次安装没有写入中文"
assert_file "$HOME_ONE/zh-cn-tool/macos/active-state.json" "首次安装没有有效状态"
assert_eq "$(tree_hash "$APP")" "$OFFICIAL_HASH" "首次安装修改了官方 App"
REPORT="$(latest_report "$HOME_ONE")"
assert_eq "$(json_value "$REPORT" resourcesReady)" "true" "资源状态不正确"
assert_eq "$(json_value "$REPORT" installationReady)" "true" "安装准备状态不正确"
assert_eq "$(json_value "$REPORT" launchAttempted)" "false" "NoRestart 不应启动程序"
assert_eq "$(json_value "$REPORT" uiLanguageVerified)" "false" "脚本不得冒充界面验收"
pass "首次安装、中文路径、官方文件不变和状态分级"

# 2. 重复安装：只保留一个 desktop 段和一个语言键，旧备份不删除。
run_tool "$APP" "$HOME_ONE" --action install --no-restart >/dev/null || fail "重复安装失败"
assert_eq "$(grep -c '^\[desktop\]$' "$HOME_ONE/config.toml")" "1" "重复安装生成重复 desktop 段"
assert_eq "$(grep -c '^localeOverride[[:space:]]*=' "$HOME_ONE/config.toml")" "1" "重复安装生成重复语言键"
BACKUP_COUNT="$(find "$HOME_ONE/zh-cn-tool/macos/backups" -type f -name '*.bak' | wc -l | tr -d ' ')"
[ "$BACKUP_COUNT" -ge 1 ] || fail "重复安装没有保留配置备份"
pass "重复安装和备份保留"

# 3. 损坏状态记录：忽略并安全重建。
printf '{broken\n' > "$HOME_ONE/zh-cn-tool/macos/active-state.json"
run_tool "$APP" "$HOME_ONE" --action install --no-restart >/dev/null || fail "损坏记录阻塞了重新安装"
assert_eq "$(json_value "$HOME_ONE/zh-cn-tool/macos/active-state.json" bundleIdentifier)" "com.openai.codex" "损坏记录未被替换"
pass "损坏状态记录恢复"

# 4. 缺失中文资源：在写配置前停止。
APP_MISSING="$CASE_ROOT/缺资源.app"; HOME_MISSING="$CASE_ROOT/缺资源数据"
create_app "$APP_MISSING" "1.0" missing-zh v1
if run_tool "$APP_MISSING" "$HOME_MISSING" --action install --no-restart >/dev/null 2>&1; then fail "缺失资源被错误接受"; fi
assert_not_file "$HOME_MISSING/config.toml" "缺资源失败后不应写配置"
assert_not_file "$HOME_MISSING/zh-cn-tool/macos/active-state.json" "缺资源失败后不应激活状态"
pass "缺失文件安全失败"

# 5. 空间不足：配置和状态保持未创建。
HOME_SPACE="$CASE_ROOT/空间不足"
if CODEX_ZH_TEST_FREE_KB=100 run_tool "$APP" "$HOME_SPACE" --action install --no-restart >/dev/null 2>&1; then fail "空间不足被错误接受"; fi
assert_not_file "$HOME_SPACE/config.toml" "空间不足后不应写配置"
assert_not_file "$HOME_SPACE/zh-cn-tool/macos/active-state.json" "空间不足后不应激活状态"
pass "空间不足预检"

# 6. 备份复制失败：原配置和无关配置不变。
HOME_COPY="$CASE_ROOT/备份失败"; mkdir -p -- "$HOME_COPY"
printf 'model = "keep-me"\n\n[desktop]\nlocaleOverride = "en-US"\n' > "$HOME_COPY/config.toml"
BEFORE_CONFIG="$(shasum -a 256 "$HOME_COPY/config.toml" | awk '{print $1}')"
if CODEX_ZH_TEST_FAIL_STAGE=backup run_tool "$APP" "$HOME_COPY" --action install --no-restart >/dev/null 2>&1; then fail "备份失败被错误接受"; fi
assert_eq "$(shasum -a 256 "$HOME_COPY/config.toml" | awk '{print $1}')" "$BEFORE_CONFIG" "备份失败改变了配置"
assert_not_file "$HOME_COPY/zh-cn-tool/macos/active-state.json" "备份失败后不应激活状态"
pass "备份复制失败保护"

# 7. 中断：写入状态前回滚原配置。
HOME_INTERRUPTED="$CASE_ROOT/中断恢复"; mkdir -p -- "$HOME_INTERRUPTED"
printf 'approval_policy = "never"\n' > "$HOME_INTERRUPTED/config.toml"
INTERRUPTED_HASH="$(shasum -a 256 "$HOME_INTERRUPTED/config.toml" | awk '{print $1}')"
if CODEX_ZH_TEST_FAIL_STAGE=state run_tool "$APP" "$HOME_INTERRUPTED" --action install --no-restart >/dev/null 2>&1; then fail "中断测试被错误接受"; fi
assert_eq "$(shasum -a 256 "$HOME_INTERRUPTED/config.toml" | awk '{print $1}')" "$INTERRUPTED_HASH" "中断后没有回滚配置"
assert_not_file "$HOME_INTERRUPTED/zh-cn-tool/macos/active-state.json" "中断后不应激活状态"
pass "安装中断回滚"

# 8. 官方升级：旧状态失效，重装后记录新版本且无关配置保留。
create_app "$APP" "26.931.100" complete v2
run_tool "$APP" "$HOME_ONE" --action status --json >/dev/null || fail "升级后状态检查失败"
REPORT="$(latest_report "$HOME_ONE")"
assert_eq "$(json_value "$REPORT" officialAppUpdated)" "true" "没有识别官方升级"
assert_eq "$(json_value "$REPORT" nextAction)" "rerun-macos-installer-after-official-update" "升级后的建议不正确"
run_tool "$APP" "$HOME_ONE" --action install --no-restart >/dev/null || fail "升级后重新安装失败"
assert_eq "$(json_value "$HOME_ONE/zh-cn-tool/macos/active-state.json" codexVersion)" "26.931.100" "状态未更新到新版"
pass "官方升级识别与重新安装"

# 9. 打开与重复打开：每次都先验证，不把进程存在当界面验收。
OPEN_LOG="$CASE_ROOT/open.log"
CODEX_ZH_TEST_OPEN_LOG="$OPEN_LOG" run_tool "$APP" "$HOME_ONE" --action open >/dev/null || fail "第一次打开失败"
CODEX_ZH_TEST_OPEN_LOG="$OPEN_LOG" run_tool "$APP" "$HOME_ONE" --action open >/dev/null || fail "重复打开失败"
assert_eq "$(wc -l < "$OPEN_LOG" | tr -d ' ')" "2" "重复打开没有复用官方启动入口"
REPORT="$(latest_report "$HOME_ONE")"
assert_eq "$(json_value "$REPORT" programRunning)" "true" "启动后未记录进程状态"
assert_eq "$(json_value "$REPORT" uiLanguageVerified)" "false" "进程存在被错误当成界面验收"
pass "启动、重复启动和界面验收边界"

# 10. 恢复英文：不删备份、不改官方 App、不改无关配置。
UPDATED_OFFICIAL_HASH="$(tree_hash "$APP")"
run_tool "$APP" "$HOME_ONE" --action restore --no-restart >/dev/null || fail "恢复英文失败"
assert_contains "$HOME_ONE/config.toml" 'localeOverride = "en-US"' "没有恢复英文"
assert_eq "$(tree_hash "$APP")" "$UPDATED_OFFICIAL_HASH" "恢复英文修改了官方 App"
[ "$(find "$HOME_ONE/zh-cn-tool/macos/backups" -type f -name '*.bak' | wc -l | tr -d ' ')" -ge "$BACKUP_COUNT" ] || fail "恢复英文删除了旧备份"
pass "恢复英文和备份保留"

# 11. Apple Silicon 与 Intel 状态分别判定；不在本机冒充真实 Intel 验收。
HOME_ARM="$CASE_ROOT/arm64"; HOME_INTEL="$CASE_ROOT/intel"
CODEX_ZH_TEST_ARCH_VALUE=arm64 CODEX_ZH_TEST_MACHINE_VALUE=arm64 run_tool "$APP" "$HOME_ARM" --action status --json >/dev/null
REPORT="$(latest_report "$HOME_ARM")"
assert_eq "$(json_value "$REPORT" architectureCompatible)" "true" "Apple Silicon 架构判断错误"
CODEX_ZH_TEST_ARCH_VALUE=x86_64 CODEX_ZH_TEST_MACHINE_VALUE=x86_64 run_tool "$APP" "$HOME_INTEL" --action status --json >/dev/null
REPORT="$(latest_report "$HOME_INTEL")"
assert_eq "$(json_value "$REPORT" architectureCompatible)" "true" "Intel 架构判断错误"
pass "Apple Silicon 与 Intel 架构分支"

printf '\n[PASS] macOS 自动回归完成：%s 组\n' "$PASS_COUNT"
