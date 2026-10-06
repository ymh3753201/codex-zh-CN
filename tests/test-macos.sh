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
    /bin/bash "$INSTALLER" --mode native --app "$app" --codex-home "$home" "$@"
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
assert_eq "$(json_value "$REPORT" settingsPrepared)" "true" "语言设置准备状态不正确"
assert_eq "$(json_value "$REPORT" installationReady)" "false" "没有实际界面确认时不应宣称翻译生效条件全部通过"
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

# 12. 路径包含竖线时，只清理工具自己创建的临时文件。
DECOY_ROOT="$CASE_ROOT/清理保护"
HOME_PIPE="$CASE_ROOT/清理保护|数据"
mkdir -p -- "$DECOY_ROOT" "$HOME_PIPE"
printf 'must-stay\n' > "$DECOY_ROOT/不可删除.txt"
run_tool "$APP" "$HOME_PIPE" --action status --json >/dev/null || fail "竖线路径状态检查失败"
assert_file "$DECOY_ROOT/不可删除.txt" "竖线路径清理误删了无关目录"
pass "竖线、中文和空格路径的安全清理"

# 13. 复杂 TOML 必须安全停止，不能误改多行字符串或点分键。
HOME_MULTILINE="$CASE_ROOT/多行 TOML"; mkdir -p -- "$HOME_MULTILINE"
printf 'student_note = """\n[desktop]\nlocaleOverride = "en-US"\n"""\n' > "$HOME_MULTILINE/config.toml"
MULTILINE_HASH="$(shasum -a 256 "$HOME_MULTILINE/config.toml" | awk '{print $1}')"
if run_tool "$APP" "$HOME_MULTILINE" --action install --no-restart >/dev/null 2>&1; then fail "多行 TOML 被错误修改"; fi
assert_eq "$(shasum -a 256 "$HOME_MULTILINE/config.toml" | awk '{print $1}')" "$MULTILINE_HASH" "多行 TOML 失败后配置发生变化"
assert_not_file "$HOME_MULTILINE/zh-cn-tool/macos/active-state.json" "多行 TOML 失败后不应激活状态"

HOME_DOTTED="$CASE_ROOT/点分 TOML"; mkdir -p -- "$HOME_DOTTED"
printf 'desktop.localeOverride = "en-US"\nmodel = "keep-me"\n' > "$HOME_DOTTED/config.toml"
DOTTED_HASH="$(shasum -a 256 "$HOME_DOTTED/config.toml" | awk '{print $1}')"
if run_tool "$APP" "$HOME_DOTTED" --action install --no-restart >/dev/null 2>&1; then fail "点分 TOML 被错误修改"; fi
assert_eq "$(shasum -a 256 "$HOME_DOTTED/config.toml" | awk '{print $1}')" "$DOTTED_HASH" "点分 TOML 失败后配置发生变化"
assert_not_file "$HOME_DOTTED/zh-cn-tool/macos/active-state.json" "点分 TOML 失败后不应激活状态"
pass "复杂 TOML 安全停止"

# 14. 收到终止信号时回滚配置，不留下未完成的启动状态，并生成报告。
HOME_SIGNAL="$CASE_ROOT/真实信号中断"; mkdir -p -- "$HOME_SIGNAL"
printf 'approval_policy = "never"\n' > "$HOME_SIGNAL/config.toml"
SIGNAL_HASH="$(shasum -a 256 "$HOME_SIGNAL/config.toml" | awk '{print $1}')"
SIGNAL_OUTPUT="$CASE_ROOT/signal-output.txt"
CODEX_ZH_TESTING=1 \
CODEX_ZH_TEST_ARCH="$(uname -m)" \
CODEX_ZH_TEST_MACHINE_ARCH="$(uname -m)" \
CODEX_ZH_TEST_WAIT_FOR_SIGNAL=1 \
/bin/bash "$INSTALLER" --app "$APP" --codex-home "$HOME_SIGNAL" --action install --no-restart > "$SIGNAL_OUTPUT" 2>&1 &
SIGNAL_PID=$!
signal_ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if grep -F -q 'localeOverride = "zh-CN"' "$HOME_SIGNAL/config.toml" 2>/dev/null; then signal_ready=1; break; fi
    sleep 0.2
done
[ "$signal_ready" -eq 1 ] || { kill -TERM "$SIGNAL_PID" 2>/dev/null || true; wait "$SIGNAL_PID" 2>/dev/null || true; fail "中断测试未进入配置事务"; }
kill -TERM "$SIGNAL_PID"
if wait "$SIGNAL_PID"; then fail "终止信号被错误当成成功"; fi
assert_eq "$(shasum -a 256 "$HOME_SIGNAL/config.toml" | awk '{print $1}')" "$SIGNAL_HASH" "终止信号后没有回滚配置"
assert_not_file "$HOME_SIGNAL/zh-cn-tool/macos/active-state.json" "终止信号后不应激活状态"
REPORT="$(latest_report "$HOME_SIGNAL")"
assert_file "$REPORT" "终止信号后没有问题报告"
assert_eq "$(json_value "$REPORT" failureStage)" "interrupted" "中断报告没有记录失败阶段"
pass "真实终止信号回滚和问题报告"

# 15. 默认状态目录不可用时，改在临时目录留下可交给助教的问题报告。
HOME_REPORT_FAIL="$CASE_ROOT/报告兜底数据"; mkdir -p -- "$HOME_REPORT_FAIL"
BLOCKED_STATE="$CASE_ROOT/状态目录被文件占用"
FALLBACK_PARENT="$CASE_ROOT/临时报告"; mkdir -p -- "$FALLBACK_PARENT"
printf 'block-directory\n' > "$BLOCKED_STATE"
if FALLBACK_OUTPUT="$(TMPDIR="$FALLBACK_PARENT" run_tool "$APP" "$HOME_REPORT_FAIL" --state-root "$BLOCKED_STATE" --action install --no-restart 2>&1)"; then
    fail "不可写状态目录被错误接受"
fi
FALLBACK_REPORT="$(printf '%s\n' "$FALLBACK_OUTPUT" | sed -n 's/^  问题报告：//p' | tail -n 1)"
assert_file "$FALLBACK_REPORT" "状态目录失败时没有生成兜底问题报告"
assert_eq "$(json_value "$FALLBACK_REPORT" failureStage)" "init-state-directory" "兜底报告没有记录失败阶段"
pass "状态目录失败时的临时问题报告"

printf '\n[PASS] macOS 自动回归完成：%s 组\n' "$PASS_COUNT"
