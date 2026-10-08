#!/bin/bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CASE="$(mktemp -d /tmp/codex-zh-package-tests.XXXXXX)"
CHECK="$ROOT/scripts/check-macos-package.sh"
REPORTS=("")
cleanup() {
    for report in "${REPORTS[@]}"; do
        case "$report" in /tmp/codex-zh-tool-package.*/report.json) rm "$report"; rmdir "$(dirname "$report")" ;; esac
    done
    case "$CASE" in /tmp/codex-zh-package-tests.*) rm -rf -- "$CASE" ;; esac
}
trap cleanup EXIT
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
value() { /usr/bin/plutil -extract "$2" raw -o - "$1"; }
assert() { [ "$1" = "$2" ] || fail "$3"; }
failed_check() {
    if /bin/bash "$CHECK" --root "$1" > "$CASE/result.json" 2> "$CASE/error.log"; then fail "错误工具包被接受"; fi
    assert "$(value "$CASE/result.json" toolPackageReady)" false "缺文件仍声称准备完成"
    assert "$(value "$CASE/result.json" failureStage)" tool-package-check "失败阶段错误"
    assert "$(value "$CASE/result.json" installationReady)" false "预检失败声称安装完成"
    assert "$(value "$CASE/result.json" launchAttempted)" false "预检失败尝试启动"
    report="$(value "$CASE/result.json" reportPath)"
    [ -f "$report" ] || fail "没有保留助教问题报告"
    REPORTS+=("$report")
}

# Reproduce a downloaded main/v0.3.4 Windows-only package without an app.
OLD="$CASE/旧 Windows 工具包"
mkdir -p "$OLD/resources"
/usr/bin/plutil -create xml1 "$OLD/resources/release.json"
/usr/bin/plutil -insert release -string 0.3.4 "$OLD/resources/release.json"
/usr/bin/plutil -convert json "$OLD/resources/release.json"
failed_check "$OLD"
assert "$(value "$CASE/result.json" problemClassification)" incomplete-or-wrong-tool-package "旧包分类错误"
printf '%s\n' "$(value "$CASE/result.json" missingFiles)" | grep -F -q scripts/install_macos.sh || fail "没有指出缺少 macOS 入口"

PACKAGE="$CASE/完整 中文 & (空格) 工具"
while IFS= read -r relative || [ -n "$relative" ]; do
    mkdir -p "$PACKAGE/$(dirname "$relative")"
    cp "$ROOT/$relative" "$PACKAGE/$relative"
done < "$ROOT/resources/macos-package-files.txt"
/bin/bash "$CHECK" --root "$PACKAGE" > "$CASE/ready.json"
assert "$(value "$CASE/ready.json" toolPackageReady)" true "完整工具被拒绝"
assert "$(value "$CASE/ready.json" installationReady)" false "文件检查冒充安装"
assert "$(value "$CASE/ready.json" uiLanguageVerified)" false "文件检查冒充界面验收"

# Missing dependency stops BEFORE official app discovery or configuration writes.
DATA="$CASE/不可修改的用户目录"
mkdir "$DATA"
printf 'model = "keep-private-test-sentinel"\n' > "$DATA/config.toml"
CONFIG_HASH="$(shasum -a 256 "$DATA/config.toml" | awk '{print $1}')"
mv "$PACKAGE/scripts/macos-copy.sh" "$PACKAGE/scripts/macos-copy.sh.saved"
if /bin/bash "$PACKAGE/scripts/install_macos.sh" --action install --no-restart --codex-home "$DATA" \
    --app "$CASE/不存在.app" > "$CASE/result.json" 2> "$CASE/error.log"; then fail "缺依赖仍进入安装"; fi
assert "$(value "$CASE/result.json" failureStage)" tool-package-check "缺依赖没有提前停止"
REPORTS+=("$(value "$CASE/result.json" reportPath)")
assert "$(shasum -a 256 "$DATA/config.toml" | awk '{print $1}')" "$CONFIG_HASH" "失败改变了配置"
[ ! -e "$DATA/zh-cn-tool" ] || fail "预检失败写入了用户状态目录"
! grep -q keep-private-test-sentinel "$CASE/result.json" || fail "报告泄露配置内容"
mv "$PACKAGE/scripts/macos-copy.sh.saved" "$PACKAGE/scripts/macos-copy.sh"

/usr/bin/plutil -replace release -string 0.1.0-preview.2 "$PACKAGE/resources/macos-release.json"
failed_check "$PACKAGE"
cp "$ROOT/resources/macos-release.json" "$PACKAGE/resources/macos-release.json"
printf '../outside\n' >> "$PACKAGE/resources/macos-package-files.txt"
failed_check "$PACKAGE"
printf '[PASS] 旧 Windows-only 包、缺依赖、混用版本、异常清单与配置保护\n'
