#!/bin/bash

# Read only the downloaded tool, never Codex.app or the user's configuration.
set -u
PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
EXPECTED_VERSION=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root|--expected-version)
            [ "$#" -ge 2 ] || { printf '缺少工具包检查参数\n' >&2; exit 2; }
            if [ "$1" = --root ]; then PACKAGE_ROOT="$2"; else EXPECTED_VERSION="$2"; fi
            shift 2 ;;
        *) printf '未知工具包检查参数\n' >&2; exit 2 ;;
    esac
done

MISSING=""
FAILURE=""
record_missing() { MISSING="${MISSING}${MISSING:+, }$1"; }
MANIFEST="$PACKAGE_ROOT/resources/macos-package-files.txt"
# These are an independent runtime contract, even if the manifest is damaged.
for relative in scripts/install_macos.sh scripts/macos-copy.sh scripts/inspect-macos-asar.js \
    scripts/macos-integrity.js scripts/check-macos-copy-paths.js scripts/check-macos-package.sh \
    scripts/macos-local.entitlements.plist resources/macos-release.json resources/macos-package-files.txt; do
    [ -f "$PACKAGE_ROOT/$relative" ] && [ ! -L "$PACKAGE_ROOT/$relative" ] || record_missing "$relative"
done
if [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then
    while IFS= read -r relative || [ -n "$relative" ]; do
        case "$relative" in
            ''|/*|*'..'*|*$'\r'*) FAILURE="工具包文件清单无效"; break ;;
        esac
        [ -f "$PACKAGE_ROOT/$relative" ] && [ ! -L "$PACKAGE_ROOT/$relative" ] || record_missing "$relative"
    done < "$MANIFEST"
fi
VERSION="$(/usr/bin/plutil -extract release raw -o - "$PACKAGE_ROOT/resources/macos-release.json" 2>/dev/null || true)"
INSTALLER_VERSION="$(/usr/bin/sed -n 's/^TOOL_VERSION="\([^"]*\)"$/\1/p' "$PACKAGE_ROOT/scripts/install_macos.sh" 2>/dev/null)"
if [ -n "$MISSING" ]; then
    FAILURE="下载的工具缺少 macOS 文件或未完整解压；请下载明确含 macOS 入口的固定版本，不要改用 main 或旧 Windows 包"
elif [ -z "$VERSION" ] || [ "$VERSION" != "$INSTALLER_VERSION" ] ||
    { [ -n "$EXPECTED_VERSION" ] && [ "$VERSION" != "$EXPECTED_VERSION" ]; }; then
    FAILURE="工具包版本记录损坏或混用了不同版本；请重新完整下载，不要只替换单个脚本"
fi

REPORT_DIR="$(/usr/bin/mktemp -d /tmp/codex-zh-tool-package.XXXXXX)" || { printf '无法生成工具包检查报告\n' >&2; exit 1; }
REPORT="$REPORT_DIR/report.json"
/usr/bin/plutil -create xml1 "$REPORT" || exit 1
put_string() { /usr/bin/plutil -insert "$1" -string "$2" "$REPORT"; }
put_bool() { /usr/bin/plutil -insert "$1" -bool "$2" "$REPORT"; }
put_string toolVersion "$VERSION"
put_string machineArchitecture "$(uname -m)"
put_string macOSVersion "$(sw_vers -productVersion 2>/dev/null || printf unknown)"
put_string missingFiles "$MISSING"
put_string failureMessage "$FAILURE"
put_bool resourcesReady NO
put_bool settingsPrepared NO
put_bool installationReady NO
put_bool launchAttempted NO
put_bool programRunning NO
put_bool uiLanguageVerified NO
if [ -n "$FAILURE" ]; then
    put_bool toolPackageReady NO
    put_bool toolIssueSuspected YES
    put_string failureStage tool-package-check
    put_string problemClassification incomplete-or-wrong-tool-package
    put_string lastResult failed
    put_string nextAction download-pinned-complete-macos-tool
    put_string reportPath "$REPORT"
    /usr/bin/plutil -convert json "$REPORT" || exit 1
    chmod 600 "$REPORT"
    printf '[错误] %s\n问题报告：%s\n' "$FAILURE" "$REPORT" >&2
    /bin/cat "$REPORT"
    exit 1
fi
put_bool toolPackageReady YES
put_bool toolIssueSuspected NO
put_string failureStage ""
put_string lastResult package-ready
put_string nextAction run-macos-installer
/usr/bin/plutil -convert json "$REPORT" || exit 1
/bin/cat "$REPORT"
# Only the successful check's own empty temporary directory is removed.
/bin/rm "$REPORT"
/bin/rmdir "$REPORT_DIR"
