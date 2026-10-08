#!/bin/bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALLER="${CODEX_ZH_MACOS_INSTALLER:-$ROOT/scripts/install_macos.sh}"
CASE="$(mktemp -d /tmp/codex-zh-language-gate.XXXXXX)"
trap 'case "$CASE" in /tmp/codex-zh-language-gate.*) rm -rf -- "$CASE" ;; esac' EXIT
APP="$CASE/中文 & (门控).app"
DATA="$CASE/数据"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/usr/bin/plutil -create xml1 "$APP/Contents/Info.plist"
for pair in 'CFBundleIdentifier com.openai.codex' 'CFBundleExecutable ChatGPT' 'CFBundleShortVersionString 26.1002.52244' 'CFBundleVersion 13536'; do
    /usr/bin/plutil -insert "${pair%% *}" -string "${pair#* }" "$APP/Contents/Info.plist"
done
printf '#!/bin/bash\nexit 0\n' > "$APP/Contents/MacOS/ChatGPT"
chmod +x "$APP/Contents/MacOS/ChatGPT"
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" gated
OFFICIAL_HASH="$(shasum -a 256 "$APP/Contents/Resources/app.asar" | awk '{print $1}')"
tool() { CODEX_ZH_TESTING=1 CODEX_ZH_TEST_ARCH="$(uname -m)" /bin/bash "$INSTALLER" --mode native --app "$APP" --codex-home "$DATA" "$@"; }
value() { /usr/bin/plutil -extract "$2" raw -o - "$1"; }
report() { find "$DATA/zh-cn-tool/macos/diagnostics" -name 'report-*.json' | sort | tail -n 1; }
assert() { [ "$1" = "$2" ] || { printf '[FAIL] %s: %s != %s\n' "$3" "$1" "$2" >&2; exit 1; }; }
tool --action install --no-restart > "$CASE/install.log"
REPORT="$(report)"
assert "$(value "$REPORT" installationReady)" false '远程翻译开关未验证时不得声称安装准备完成'
assert "$(value "$REPORT" settingsPrepared)" true '语言配置应该已准备好'
assert "$(value "$REPORT" codexVersion)" 26.1002.52244 '新版 Codex 版本应保留'
assert "$(value "$REPORT" buildVersion)" 13536 '新版 Codex 构建号应保留'
assert "$(value "$REPORT" languageGateDetected)" true '必须发现主界面远程门控'
assert "$(value "$REPORT" languageGateEvidence.0.defaultEnabled)" false '必须记录主界面默认值为 false'
assert "$(value "$REPORT" languageGateEvidence.1.defaultEnabled)" true '设置页默认值不能被当成主界面默认值'
assert "$(value "$REPORT" remoteLanguageGateValue)" unknown '静态分析不能冒充账号远程开关值'
assert "$(value "$REPORT" lastResult)" partial '仅写入设置应报告部分完成'
tool --action status --ui-result english --json > "$CASE/english.json"
assert "$(value "$CASE/english.json" toolIssueSuspected)" true '实际英文必须识别为工具兼容缺口'
assert "$(value "$CASE/english.json" failureStage)" ui-language-verification '必须记录界面验收失败阶段'
assert "$(value "$CASE/english.json" installationReady)" false '英文结果不应报准备完成'
tool --action status --ui-result chinese --json > "$CASE/chinese.json"
assert "$(value "$CASE/chinese.json" uiLanguageVerified)" true '只能本次明确人工确认后登记中文'
assert "$(value "$CASE/chinese.json" installationReady)" true '本次已确认中文可通过门控验收'
tool --action status --json > "$CASE/fresh.json"
assert "$(value "$CASE/fresh.json" uiLanguageVerified)" false '历史界面结果不能冒充本次验收'
assert "$(value "$CASE/fresh.json" installationReady)" false '不能永久假设远程门控已开启'
tool --action open --no-restart >/dev/null
assert "$(value "$(report)" lastResult)" partial '检测到进程仍不等于汉化完成'
assert "$(shasum -a 256 "$APP/Contents/Resources/app.asar" | awk '{print $1}')" "$OFFICIAL_HASH" '检查门控不应改变官方资源'

# 同样的 ASAR，不同构建号：历史状态必须失效。
/usr/bin/plutil -replace CFBundleVersion -string 13537 "$APP/Contents/Info.plist"
tool --action status --json > "$CASE/updated.json"
assert "$(value "$CASE/updated.json" officialAppUpdated)" true '构建号变化必须识别为官方升级'
tool --action install --no-restart >/dev/null

# 未识别的新语言逻辑只能报告未知，不应自行改程序或报准备完成。
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" unknown-gate
tool --action install --no-restart >/dev/null
assert "$(value "$(report)" languageGateStatus)" unrecognized '新版未知语言逻辑必须被识别'
assert "$(value "$(report)" installationReady)" false '未知语言逻辑不得报准备完成'

# 中文文件名存在，但实际字节不匹配：必须在写配置前失败。
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" corrupt-zh
CONFIG_HASH="$(shasum -a 256 "$DATA/config.toml" | awk '{print $1}')"
if tool --action install --no-restart >/dev/null 2>&1; then printf '[FAIL] 损坏的中文资源被错误接受\n' >&2; exit 1; fi
assert "$(shasum -a 256 "$DATA/config.toml" | awk '{print $1}')" "$CONFIG_HASH" '损坏资源不得修改原配置'
assert "$(value "$(report)" resourcesReady)" false '资源哈希不符必须报告失败'

# 损坏 ASAR 即使声称界面中文也不应登记验收。
if tool --action status --ui-result chinese --json > "$CASE/invalid.json" 2>/dev/null; then printf '[FAIL] 损坏资源仍接受中文验收\n' >&2; exit 1; fi
assert "$(value "$CASE/invalid.json" uiLanguageVerified)" false '安全前提不满足时不得登记界面验收'
tool --action restore --no-restart >/dev/null
grep -F -q 'localeOverride = "en-US"' "$DATA/config.toml"

# plist 的内嵌 ASAR 文件头哈希必须与真实文件一致。
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" gated
/usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity:Resources/app.asar dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity:Resources/app.asar:hash string 0000000000000000000000000000000000000000000000000000000000000000' "$APP/Contents/Info.plist"
CONFIG_HASH="$(shasum -a 256 "$DATA/config.toml" | awk '{print $1}')"
if tool --action install --no-restart >/dev/null 2>&1; then printf '[FAIL] 错误的内嵌文件头哈希被接受\n' >&2; exit 1; fi
assert "$(shasum -a 256 "$DATA/config.toml" | awk '{print $1}')" "$CONFIG_HASH" '内嵌哈希不符不得修改配置'
assert "$(value "$(report)" failureStage)" check-resources '必须明确记录资源失败阶段'
printf '[PASS] 远程门控、未知逻辑、字节和内嵌哈希损坏、构建升级、人工确认和恢复回归\n'
