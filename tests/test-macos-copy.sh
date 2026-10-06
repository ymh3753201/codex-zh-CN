#!/bin/bash
set -Eeu
trap 'printf "[FAIL] fixture line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALLER="${CODEX_ZH_MACOS_INSTALLER:-$ROOT/scripts/install_macos.sh}"
CASE="$(mktemp -d /tmp/codex-zh-copy-tests.XXXXXX)"
trap 'case "$CASE" in /tmp/codex-zh-copy-tests.*) rm -rf -- "$CASE" ;; esac' EXIT
APP="$CASE/官方 中文 & (空格).app"
DATA="$CASE/用户 中文 & (数据)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DATA"
/usr/bin/plutil -create xml1 "$APP/Contents/Info.plist"
for pair in 'CFBundleIdentifier com.openai.codex' 'CFBundleExecutable ChatGPT' 'CFBundleShortVersionString 26.930.51102' 'CFBundleVersion 13100'; do
    /usr/bin/plutil -insert "${pair%% *}" -string "${pair#* }" "$APP/Contents/Info.plist"
done
printf '#!/bin/bash\nexit 0\n' > "$APP/Contents/MacOS/ChatGPT"; chmod +x "$APP/Contents/MacOS/ChatGPT"
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" gated
printf 'model = "keep-model"\n[desktop]\nlocaleOverride = "en-US"\n' > "$DATA/config.toml"
printf 'private conversation sentinel' > "$DATA/conversation-sentinel"
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
OFFICIAL="$(sha "$APP/Contents/Resources/app.asar")"; INFO="$(sha "$APP/Contents/Info.plist")"
PRIVATE="$(sha "$DATA/conversation-sentinel")"
tool() {
    if CODEX_ZH_TESTING=1 CODEX_ZH_TEST_ARCH="$(uname -m)" /bin/bash "$INSTALLER" --app "$APP" --codex-home "$DATA" "$@"; then return 0; else
        fixture_status=$?
        # Fixtures contain no accounts or real user data; expose the failure stage in CI.
        fixture_report="$(find "$DATA/zh-cn-tool/macos/diagnostics" -name 'report-*.json' | sort | tail -n 1)"
        [ -z "$fixture_report" ] || /bin/cat "$fixture_report" >&2
        if [ -n "$fixture_report" ]; then
            fixture_log="$(/usr/bin/plutil -extract logPath raw -o - "$fixture_report")"
            case "$fixture_log" in "$CASE"/*) /bin/cat "$fixture_log" >&2 ;; esac
        fi
        return "$fixture_status"
    fi
}
value() { /usr/bin/plutil -extract "$2" raw -o - "$1"; }
report() { find "$DATA/zh-cn-tool/macos/diagnostics" -name 'report-*.json' | sort | tail -n 1; }
assert() { [ "$1" = "$2" ] || { printf '[FAIL] %s: %s != %s\n' "$3" "$1" "$2" >&2; exit 1; }; }
tool --action install --no-restart >/dev/null
STATE="$DATA/zh-cn-tool/macos/active-state.json"
assert "$(value "$STATE" mode)" zh-CN '静态开关存在也必须先用官方设置'
assert "$([ ! -d "$DATA/zh-cn-tool/macos/copies" ] && echo true)" true '默认首次安装不得创建副本'
tool --action status --ui-result chinese --json > "$CASE/native-chinese.json"
tool --action install --no-restart >/dev/null
assert "$(value "$STATE" mode)" zh-CN '已确认官方中文不得创建副本'
tool --action status --ui-result english --json > "$CASE/native-english.json"
assert "$(value "$STATE" nativeUiEnglishConfirmed)" true '实际英文反馈须绑定当前版本'
tool --action status --json > "$CASE/native-later.json"
assert "$(value "$CASE/native-later.json" nativeUiEnglishConfirmed)" true '后续报告应如实显示当前版本英文反馈'
assert "$(value "$CASE/native-later.json" nextAction)" run-explicit-copy-fallback-after-native-ui-failure '后续建议与下次安装行为一致'
tool --action install --no-restart >/dev/null
COPY="$(value "$STATE" copyPath)"
assert "$(value "$(report)" installationReady)" true '副本资源与本地签名准备完成'
assert "$(value "$STATE" copyActivated)" false '不重启安装不得假装副本已经启动'
assert "$(value "$(report)" uiLanguageVerified)" false '脚本成功不得冒充界面验收'
assert "$(value "$(report)" lastResult)" partial '等待界面验收'
# Execute the actual patched fixture gate, not a separately reimplemented function.
node --input-type=module - "$COPY/Contents/Resources/app.asar" <<'JS'
import fs from 'node:fs'; import vm from 'node:vm'; import assert from 'node:assert/strict';
const b=fs.readFileSync(process.argv[2]), base=8+b.readUInt32LE(4), h=JSON.parse(b.subarray(16,16+b.readUInt32LE(12)));
const e=h.files.webview.files.assets.files['app-initial-test.js'];
const source=b.subarray(base+Number(e.offset),base+Number(e.offset)+e.size).toString();
const context={layer:()=>({get:()=>false}),loadMessages:l=>l==='zh-CN'?'中文词条':null};
assert.equal(vm.runInNewContext(source+';provider({localeOverride:"zh-CN"})',context),'中文词条');
console.log('[PASS] 远程开关 false 时执行副本真实代码仍加载中文');
JS
tool --mode copy --action install --no-restart >/dev/null
assert "$(value "$STATE" copyPath)" "$COPY" '重复安装应复用完整副本'
OPEN_LOG="$CASE/open-log"
if CODEX_ZH_TEST_OFFICIAL_RUNNING=1 CODEX_ZH_TEST_OPEN_LOG="$OPEN_LOG" tool --action open >/dev/null 2>&1; then exit 1; fi
[ ! -f "$OPEN_LOG" ]
assert "$(value "$STATE" copyActivated)" false '官方正在运行时不得启动副本或结束官方任务'
CODEX_ZH_TEST_OPEN_LOG="$OPEN_LOG" tool --action open >/dev/null
CODEX_ZH_TEST_OPEN_LOG="$OPEN_LOG" tool --action open >/dev/null
assert "$(value "$STATE" copyActivated)" true '实际启动后才激活'
assert "$(head -n 1 "$OPEN_LOG")" "$COPY" '必须启动独立副本而不是官方程序'
tool --action status --ui-result chinese --json > "$CASE/chinese.json"
assert "$(value "$CASE/chinese.json" uiLanguageVerified)" true '本次人工确认中文'
tool --action status --ui-result english --json > "$CASE/english.json"
assert "$(value "$CASE/english.json" toolIssueSuspected)" true '实际英文应报告兼容失败'

# Missing copy file and damaged state cannot be used as launch targets.
mv "$COPY/Contents/Resources/app.asar" "$COPY/Contents/Resources/app.asar.saved"
if tool --action open >/dev/null 2>&1; then exit 1; fi
tool --mode copy --action install --no-restart >/dev/null
assert "$([ "$(value "$STATE" copyPath)" != "$COPY" ] && echo true)" true '缺失副本重新准备，保留旧副本'
[ -f "$COPY/Contents/Resources/app.asar.saved" ]
printf '{broken' > "$STATE"
tool --mode copy --action install --no-restart >/dev/null
COPY="$(value "$STATE" copyPath)"

# Copy/space/signature/state interruptions leave previous state and configuration untouched.
for failure in copy copy-signature state; do
    /usr/bin/plutil -replace CFBundleVersion -string "$failure" "$APP/Contents/Info.plist"
    STATE_HASH="$(sha "$STATE")"; CONFIG_HASH="$(sha "$DATA/config.toml")"
    if CODEX_ZH_TEST_FAIL_STAGE="$failure" tool --mode copy --action install --no-restart >/dev/null 2>&1; then exit 1; fi
    assert "$(sha "$STATE")" "$STATE_HASH" "$failure 后旧启动记录不变"
    assert "$(sha "$DATA/config.toml")" "$CONFIG_HASH" "$failure 后配置回滚"
done
if CODEX_ZH_TEST_FREE_KB=1 tool --mode copy --action install --no-restart >/dev/null 2>&1; then exit 1; fi
assert "$(sha "$STATE")" "$STATE_HASH" '空间不足不激活'
/usr/bin/plutil -replace CFBundleVersion -string 13101 "$APP/Contents/Info.plist"
tool --mode copy --action install --no-restart >/dev/null
assert "$([ "$(value "$STATE" copyPath)" != "$COPY" ] && echo true)" true '官方升级必须生成新副本'
assert "$(value "$STATE" copyActivated)" false '升级后的副本未启动前不得激活'
if CODEX_ZH_TEST_OPEN_FAIL=1 tool --action open >/dev/null 2>&1; then exit 1; fi
assert "$(value "$STATE" copyActivated)" false '启动失败不得激活'
if tool --action open >/dev/null 2>&1; then printf '[FAIL] 曾失败的副本再次成为启动目标\n' >&2; exit 1; fi
tool --action status --json > "$CASE/blocked.json"
assert "$(value "$CASE/blocked.json" stateValid)" false '失败副本状态必须失效'
tool --mode copy --action install --no-restart >/dev/null
GOOD_COPY="$(value "$STATE" copyPath)"
STATE_SAVED="$CASE/state-saved.json"; cp "$STATE" "$STATE_SAVED"
/usr/bin/plutil -replace copyPath -string "$DATA/zh-cn-tool/macos/copies/copy.fake/../../Codex中文版.app" "$STATE"
if tool --action open >/dev/null 2>&1; then printf '[FAIL] 越界路径成为启动目标\n' >&2; exit 1; fi
cp "$STATE_SAVED" "$STATE"
/usr/bin/plutil -replace mode -string unknown-mode "$STATE"
tool --action status --json > "$CASE/bad-mode.json"
assert "$(value "$CASE/bad-mode.json" stateValid)" false '未知状态模式不得被接受'
cp "$STATE_SAVED" "$STATE"
QUIT_LOG="$CASE/quit-log"
CODEX_ZH_TEST_QUIT_LOG="$QUIT_LOG" CODEX_ZH_TEST_OPEN_LOG="$OPEN_LOG" tool --action restore --restart >/dev/null
assert "$(head -n 1 "$QUIT_LOG")" "$GOOD_COPY" '恢复时先退出受管副本而不是只退出官方'
assert "$(tail -n 1 "$OPEN_LOG")" "$APP" '恢复时打开官方英文目标'
assert "$(value "$STATE" mode)" english '恢复后不再以中文副本为目标'
grep -F -q 'localeOverride = "en-US"' "$DATA/config.toml"
grep -F -q 'model = "keep-model"' "$DATA/config.toml"
assert "$(sha "$APP/Contents/Resources/app.asar")" "$OFFICIAL" '官方资源不得改变'
/usr/bin/plutil -replace CFBundleVersion -string 13100 "$APP/Contents/Info.plist"
assert "$(sha "$APP/Contents/Info.plist")" "$INFO" '官方文件不得改变'
assert "$(sha "$DATA/conversation-sentinel")" "$PRIVATE" '对话等无关文件必须保持不变'

# A killed launch observation must poison the copy even if it was previously active.
tool --mode copy --action install --no-restart >/dev/null
tool --action open >/dev/null
READY="$CASE/signal-ready"
CODEX_ZH_TEST_COPY_WAIT_FOR_SIGNAL=1 CODEX_ZH_TEST_SIGNAL_READY="$READY" tool --action open >/dev/null 2>&1 &
SIGNAL_PID=$!
# tool is a shell function; signal its actual installer child, not the CI shell.
WAITED=0
while [ ! -f "$READY" ] && [ "$WAITED" -lt 30 ]; do sleep 1; WAITED=$((WAITED + 1)); done
[ -f "$READY" ] || exit 1
CHILD_PID="$(pgrep -P "$SIGNAL_PID" | head -n 1)"
[ -n "$CHILD_PID" ] || exit 1
kill -TERM "$CHILD_PID"
if wait "$SIGNAL_PID"; then exit 1; fi
if tool --action open >/dev/null 2>&1; then printf '[FAIL] 中断副本再次成为启动目标\n' >&2; exit 1; fi

# No writer may escape through a copied bundle link, including Info, framework or helpers.
for target in 'Contents/Info.plist' 'Contents/Resources/app.asar' 'Contents/Frameworks/External' 'Contents/Helpers/External.app'; do
    SAVED="$CASE/link-saved"
    if [ -e "$APP/$target" ]; then mv "$APP/$target" "$SAVED"; else mkdir -p "$(dirname "$APP/$target")"; fi
    SOURCE="$CASE/external-target"
    if [ -f "$SAVED" ]; then cp "$SAVED" "$SOURCE"; else mkdir -p "$SOURCE"; fi
    ln -s "$SOURCE" "$APP/$target"
    CONFIG_HASH="$(sha "$DATA/config.toml")"
    if tool --mode copy --action install --no-restart >/dev/null 2>&1; then exit 1; fi
    assert "$(sha "$DATA/config.toml")" "$CONFIG_HASH" '越界链接安装不写配置'
    if [ -f "$SAVED" ]; then assert "$(sha "$SOURCE")" "$(sha "$SAVED")" '越界文件不得被写入'; fi
    rm "$APP/$target"
    if [ -e "$SAVED" ]; then mv "$SAVED" "$APP/$target"; fi
    if [ -f "$SOURCE" ]; then rm "$SOURCE"; else rmdir "$SOURCE"; fi
done

# Defense in depth: direct invocation with a fake source cannot write an official file.
GUARD_ROOT="$DATA/zh-cn-tool/macos/copies/copy.guard/Codex中文版.app"
mkdir -p "$GUARD_ROOT"
if /usr/bin/osascript -l JavaScript "$ROOT/scripts/inspect-macos-asar.js" "$APP/Contents/Resources/app.asar" --patch-copy "$CASE/fake" "$GUARD_ROOT" "$OFFICIAL" >/dev/null 2>&1; then exit 1; fi
assert "$(sha "$APP/Contents/Resources/app.asar")" "$OFFICIAL" '直接调用写入函数不得修改官方文件'
mkdir -p "$GUARD_ROOT/Contents/Resources"
ln "$APP/Contents/Resources/app.asar" "$GUARD_ROOT/Contents/Resources/app.asar"
if /usr/bin/osascript -l JavaScript "$ROOT/scripts/check-macos-copy-paths.js" "$GUARD_ROOT" >/dev/null 2>&1; then exit 1; fi
if /usr/bin/osascript -l JavaScript "$ROOT/scripts/inspect-macos-asar.js" "$GUARD_ROOT/Contents/Resources/app.asar" --patch-copy "$APP/Contents/Resources/app.asar" "$GUARD_ROOT" "$OFFICIAL" >/dev/null 2>&1; then exit 1; fi
assert "$(sha "$APP/Contents/Resources/app.asar")" "$OFFICIAL" '共享硬链接写入须拒绝且源文件不变'
rm "$GUARD_ROOT/Contents/Resources/app.asar"

tool --mode copy --action install --no-restart >/dev/null
HARD_COPY="$(value "$STATE" copyPath)"
mv "$HARD_COPY/Contents/Resources/app.asar" "$HARD_COPY/Contents/Resources/app.asar.saved"
cp "$HARD_COPY/Contents/Resources/app.asar.saved" "$CASE/external-asar"
ln "$CASE/external-asar" "$HARD_COPY/Contents/Resources/app.asar"
EXTERNAL_HASH="$(sha "$CASE/external-asar")"
if tool --action open >/dev/null 2>&1; then exit 1; fi
assert "$(sha "$CASE/external-asar")" "$EXTERNAL_HASH" '受管副本中的共享硬链接不得被使用或修改'
rm "$HARD_COPY/Contents/Resources/app.asar"
mv "$HARD_COPY/Contents/Resources/app.asar.saved" "$HARD_COPY/Contents/Resources/app.asar"

# An old native failure must not force a fallback after an official upgrade.
tool --mode native --action install --no-restart >/dev/null
tool --action status --ui-result english --json >/dev/null
/usr/bin/plutil -replace CFBundleVersion -string 13102 "$APP/Contents/Info.plist"
tool --action install --no-restart >/dev/null
assert "$(value "$STATE" mode)" zh-CN '升级后必须重新优先官方设置'
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" unknown-gate
CONFIG_HASH="$(sha "$DATA/config.toml")"
if tool --mode copy --action install --no-restart >/dev/null 2>&1; then exit 1; fi
assert "$(sha "$DATA/config.toml")" "$CONFIG_HASH" '未知翻译逻辑不得猜测修改'
printf '[PASS] 独立副本首次/重复安装、损坏状态、缺失文件、空间/复制/签名/状态失败、中文路径、官方升级、启动失败、恢复及数据保护\n'
