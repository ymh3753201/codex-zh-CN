#!/bin/bash
# GitHub-only real codesign integration with a synthetic app. Never launches it.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CASE="$(mktemp -d /tmp/codex-zh-signing-tests.XXXXXX)"
trap 'case "$CASE" in /tmp/codex-zh-signing-tests.*) rm -rf -- "$CASE" ;; esac' EXIT
APP="$CASE/签名 夹具.app"
DATA="$CASE/隔离数据"
FRAMEWORK="$APP/Contents/Frameworks/Codex Framework.framework"
VERSION="$FRAMEWORK/Versions/A"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$VERSION/Resources" "$VERSION/Helpers"
node "$ROOT/tests/make-macos-fixture.mjs" "$APP/Contents/Resources/app.asar" gated
HEADER="$(node "$ROOT/tests/make-macos-signing-source.mjs" "$APP/Contents/Resources/app.asar" "$CASE/test.c")"
clang "$CASE/test.c" -o "$APP/Contents/MacOS/ChatGPT"
clang -dynamiclib "$CASE/test.c" -Wl,-install_name,@rpath/Codex\ Framework.framework/Versions/A/Codex\ Framework -o "$VERSION/Codex Framework"
/usr/bin/plutil -create xml1 "$APP/Contents/Info.plist"
for pair in 'CFBundleIdentifier com.openai.codex' 'CFBundleExecutable ChatGPT' 'CFBundleShortVersionString 26.930.51102' 'CFBundleVersion 13100' 'CFBundlePackageType APPL'; do
    /usr/bin/plutil -insert "${pair%% *}" -string "${pair#* }" "$APP/Contents/Info.plist"
done
/usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity:Resources/app.asar dict' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity:Resources/app.asar:algorithm string SHA256' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :ElectronAsarIntegrity:Resources/app.asar:hash string $HEADER" "$APP/Contents/Info.plist"
cp "$APP/Contents/Info.plist" "$VERSION/Resources/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Codex Framework' "$VERSION/Resources/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundlePackageType FMWK' "$VERSION/Resources/Info.plist"
HELPER="$VERSION/Helpers/Codex Helper.app"
mkdir -p "$HELPER/Contents/MacOS"
cp "$APP/Contents/MacOS/ChatGPT" "$HELPER/Contents/MacOS/ChatGPT"
cp "$APP/Contents/Info.plist" "$HELPER/Contents/Info.plist"
ln -s A "$FRAMEWORK/Versions/Current"
ln -s 'Versions/Current/Codex Framework' "$FRAMEWORK/Codex Framework"
ln -s 'Versions/Current/Resources' "$FRAMEWORK/Resources"
ln -s 'Versions/Current/Helpers' "$FRAMEWORK/Helpers"
/usr/bin/codesign --force --sign - "$HELPER"
/usr/bin/codesign --force --sign - "$FRAMEWORK"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
SOURCE_ASAR="$(sha "$APP/Contents/Resources/app.asar")"
SOURCE_FRAMEWORK="$(sha "$VERSION/Codex Framework")"
SOURCE_INFO="$(sha "$APP/Contents/Info.plist")"
if ! CODEX_ZH_TESTING=1 CODEX_ZH_TEST_REAL_SIGNING=1 CODEX_ZH_TEST_ARCH="$(uname -m)" /bin/bash "$ROOT/scripts/install_macos.sh" --mode copy --app "$APP" --codex-home "$DATA" --action install --no-restart >/dev/null; then
    # Only synthetic fixture logs, never a user's installation or account.
    find "$DATA/zh-cn-tool/macos/logs" -name '*.log' -exec /bin/cat {} \;
    exit 1
fi
STATE="$DATA/zh-cn-tool/macos/active-state.json"
COPY="$(/usr/bin/plutil -extract copyPath raw -o - "$STATE")"
/usr/bin/codesign --verify --deep --strict "$COPY"
/usr/bin/codesign -dv --verbose=4 "$COPY" 2>&1 | grep -q '^Signature=adhoc$'
/usr/bin/codesign -dv --verbose=4 "$COPY" 2>&1 | grep -q 'runtime'
[ "$(sha "$APP/Contents/Resources/app.asar")" = "$SOURCE_ASAR" ]
[ "$(sha "$VERSION/Codex Framework")" = "$SOURCE_FRAMEWORK" ]
[ "$(sha "$APP/Contents/Info.plist")" = "$SOURCE_INFO" ]
[ "$(/usr/bin/plutil -extract copyActivated raw -o - "$STATE")" = false ]
printf '[PASS] 真实 Mach-O 编译、内部链接、资源完整性及框架/子程序/应用本地签名；不启动夹具，不代表 Codex 界面验收\n'
