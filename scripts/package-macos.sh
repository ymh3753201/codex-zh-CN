#!/bin/bash

set -eu

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RELEASE_JSON="$PROJECT_ROOT/resources/macos-release.json"
OUTPUT_DIR="${1:-$PROJECT_ROOT/dist}"
VERSION="$(/usr/bin/plutil -extract release raw -o - "$RELEASE_JSON")"
FOLDER_NAME="codex-zh-CN-macOS-v$VERSION"
ZIP_PATH="$OUTPUT_DIR/$FOLDER_NAME.zip"
SHA_PATH="$OUTPUT_DIR/$FOLDER_NAME.sha256"
STAGE_PARENT="$(mktemp -d /tmp/codex-zh-macos-package.XXXXXX)"
STAGE_ROOT="$STAGE_PARENT/$FOLDER_NAME"

cleanup() {
    case "$STAGE_PARENT" in /tmp/codex-zh-macos-package.*) rm -rf -- "$STAGE_PARENT" ;; esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p -- "$OUTPUT_DIR" "$STAGE_ROOT"
/bin/bash "$PROJECT_ROOT/scripts/check-macos-package.sh" >/dev/null
while IFS= read -r relative || [ -n "$relative" ]; do
    case "$relative" in ''|/*|*'..'*|*$'\r'*) printf '发布清单路径无效\n' >&2; exit 1 ;; esac
    source_path="$PROJECT_ROOT/$relative"
    [ -f "$source_path" ] || { printf '发布文件缺失：%s\n' "$source_path" >&2; exit 1; }
    target_path="$STAGE_ROOT/$relative"
    mkdir -p -- "$(dirname "$target_path")"
    cp -p -- "$source_path" "$target_path"
done < "$PROJECT_ROOT/resources/macos-package-files.txt"

chmod +x "$STAGE_ROOT"/*.command "$STAGE_ROOT/scripts/install_macos.sh"
find "$STAGE_ROOT" -exec touch -t 202001010000 {} +

case "$ZIP_PATH" in "$OUTPUT_DIR"/codex-zh-CN-macOS-v*.zip) ;; *) printf '拒绝覆盖异常路径：%s\n' "$ZIP_PATH" >&2; exit 1 ;; esac
case "$SHA_PATH" in "$OUTPUT_DIR"/codex-zh-CN-macOS-v*.sha256) ;; *) printf '拒绝覆盖异常路径：%s\n' "$SHA_PATH" >&2; exit 1 ;; esac
[ ! -e "$ZIP_PATH" ] || rm -f -- "$ZIP_PATH"
[ ! -e "$SHA_PATH" ] || rm -f -- "$SHA_PATH"

(
    cd "$STAGE_PARENT"
    find "$FOLDER_NAME" -print | LC_ALL=C sort | /usr/bin/zip -X -q "$ZIP_PATH" -@
)

ZIP_HASH="$(/usr/bin/shasum -a 256 "$ZIP_PATH" | /usr/bin/awk '{print $1}')"
printf '%s  %s\n' "$ZIP_HASH" "$(basename "$ZIP_PATH")" > "$SHA_PATH"

printf '[成功] macOS 工具包：%s\n' "$ZIP_PATH"
printf '[成功] SHA-256：%s\n' "$ZIP_HASH"
printf '[信息] 校验文件：%s\n' "$SHA_PATH"
