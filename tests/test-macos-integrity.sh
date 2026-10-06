#!/bin/bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CASE="$(mktemp -d /tmp/codex-zh-integrity-tests.XXXXXX)"
trap 'case "$CASE" in /tmp/codex-zh-integrity-tests.*) rm -rf -- "$CASE" ;; esac' EXIT
OLD="$(printf '%064d' 0 | tr 0 1)"; NEW="$(printf '%064d' 0 | tr 0 2)"
for mode in arm64 intel universal; do
    BUNDLE="$CASE/copies/copy.$mode/Codex中文版.app"
    mkdir -p "$BUNDLE/Contents/Frameworks"
    node "$ROOT/tests/make-macos-integrity-fixture.mjs" "$CASE/$mode" "$mode"
    cp "$CASE/$mode" "$BUNDLE/Contents/Frameworks/binary"
    HASH="$(shasum -a 256 "$CASE/$mode" | awk '{print $1}')"
    /usr/bin/osascript -l JavaScript "$ROOT/scripts/macos-integrity.js" "$BUNDLE/Contents/Frameworks/binary" "$OLD" "$NEW" "$BUNDLE" "$CASE/$mode" "$HASH" > "$CASE/result"
    node --input-type=module - "$BUNDLE/Contents/Frameworks/binary" "$mode" <<'JS'
import fs from 'node:fs'; import crypto from 'node:crypto'; import assert from 'node:assert/strict';
const b=fs.readFileSync(process.argv[2]), digest=crypto.createHash('sha256').update('Resources/app.asarSHA256'+'2'.repeat(64)).digest();
for(const base of process.argv[3]==='universal'?[256,512]:[0]) {
  assert.equal(b[base+216],1); assert.equal(b[base+217],1);
  assert.deepEqual(b.subarray(base+218,base+250),digest);
}
JS
done
for mode in bad-hash bad-version bad-size truncated; do
    node "$ROOT/tests/make-macos-integrity-fixture.mjs" "$CASE/$mode" "$mode"
    BEFORE="$(shasum -a 256 "$CASE/$mode")"
    BUNDLE="$CASE/copies/copy.$mode/Codex中文版.app"
    mkdir -p "$BUNDLE/Contents/Frameworks"
    cp "$CASE/$mode" "$BUNDLE/Contents/Frameworks/binary"
    HASH="${BEFORE%% *}"
    if /usr/bin/osascript -l JavaScript "$ROOT/scripts/macos-integrity.js" "$BUNDLE/Contents/Frameworks/binary" "$OLD" "$NEW" "$BUNDLE" "$CASE/$mode" "$HASH" >/dev/null 2>&1; then exit 1; fi
    [ "$(shasum -a 256 "$CASE/$mode")" = "$BEFORE" ]
    [ "$(shasum -a 256 "$BUNDLE/Contents/Frameworks/binary" | awk '{print $1}')" = "$HASH" ]
done
if /usr/bin/osascript -l JavaScript "$ROOT/scripts/macos-integrity.js" "$CASE/arm64" "$OLD" "$NEW" "$BUNDLE" "$CASE/intel" "$HASH" >/dev/null 2>&1; then exit 1; fi
BUNDLE="$CASE/copies/copy.hardlink/Codex中文版.app"
mkdir -p "$BUNDLE/Contents/Frameworks"
ln "$CASE/arm64" "$BUNDLE/Contents/Frameworks/binary"
HASH="$(shasum -a 256 "$CASE/arm64" | awk '{print $1}')"
if /usr/bin/osascript -l JavaScript "$ROOT/scripts/macos-integrity.js" "$BUNDLE/Contents/Frameworks/binary" "$OLD" "$NEW" "$BUNDLE" "$CASE/arm64" "$HASH" >/dev/null 2>&1; then exit 1; fi
[ "$(shasum -a 256 "$CASE/arm64" | awk '{print $1}')" = "$HASH" ]
printf '[PASS] Apple Silicon/Intel/Universal 内嵌校验更新；未知版本、损坏和截断不写文件；未关闭完整性验证\n'
