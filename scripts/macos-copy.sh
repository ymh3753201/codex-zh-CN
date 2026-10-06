# Sourced by install_macos.sh; macOS system tools only.
COPY_PATH=""
COPY_VALID=false
COPY_ACTIVATED=false
COPY_SIGNATURE_KIND="none"
COPY_NOTARIZATION_ACCEPTED=false
COPY_QUARANTINED=false
COPY_ASAR_HASH=""
COPY_INFO_HASH=""
COPY_SOURCE_HASH=""
COPY_ERROR=""
INSTALL_MODE="auto"
EFFECTIVE_MODE="native"

copy_hash() { /usr/bin/shasum -a 256 "$1" 2>/dev/null | /usr/bin/awk '{print $1}'; }

copy_paths_confined() {
    /usr/bin/osascript -l JavaScript "$SCRIPT_DIR/check-macos-copy-paths.js" "$COPY_PATH" >> "$LOG_FILE" 2>&1 || {
        COPY_ERROR="副本包含越界链接、共享硬链接或损坏路径"; FAILURE_MESSAGE="$COPY_ERROR"; return 1;
    }
}

copy_signature() {
    [ "${CODEX_ZH_TESTING:-0}" != 1 ] || [ "${CODEX_ZH_TEST_REAL_SIGNING:-0}" = 1 ] || {
        [ "${CODEX_ZH_TEST_FAIL_STAGE:-}" != copy-signature ]
        return
    }
    /usr/bin/codesign --verify --deep --strict "$COPY_PATH" >> "$LOG_FILE" 2>&1 || return 1
    copy_signature_text="$(/usr/bin/codesign -dv --verbose=4 "$COPY_PATH" 2>&1)"
    printf '%s\n' "$copy_signature_text" | grep -q '^Signature=adhoc$' || return 1
    # A local signature is NOT OpenAI's signature or Apple notarization.
    COPY_SIGNATURE_KIND="local-ad-hoc"
    COPY_NOTARIZATION_ACCEPTED=false
    /usr/sbin/spctl --assess --type execute "$COPY_PATH" >> "$LOG_FILE" 2>&1 && COPY_NOTARIZATION_ACCEPTED=true
    return 0
}

validate_copy() {
    COPY_VALID=false
    COPY_ERROR=""
    # Never accept an arbitrary path from a damaged state file as a launch target.
    case "$COPY_PATH" in "$STATE_ROOT"/copies/copy.*/Codex中文版.app) ;; *) COPY_ERROR="副本路径不属于工具管理目录"; return 1 ;; esac
    [ "$(dirname "$(dirname "$COPY_PATH")")" = "$STATE_ROOT/copies" ] || { COPY_ERROR="副本路径包含越界目录"; return 1; }
    [ ! -L "$STATE_ROOT/copies" ] && [ ! -L "$(dirname "$COPY_PATH")" ] && [ ! -L "$COPY_PATH" ] || return 1
    [ ! -f "$(dirname "$COPY_PATH")/launch-failed" ] || { COPY_ERROR="这个副本曾启动失败，请重新安装；失败副本不会作为启动目标"; return 1; }
    copy_paths_confined || return 1
    [ -f "$COPY_PATH/Contents/MacOS/$(plist_value "$COPY_PATH/Contents/Info.plist" CFBundleExecutable)" ] || return 1
    [ "$(copy_hash "$COPY_PATH/Contents/Resources/app.asar")" = "$COPY_ASAR_HASH" ] || { COPY_ERROR="副本资源缺失或已改变"; return 1; }
    [ "$(copy_hash "$COPY_PATH/Contents/Info.plist")" = "$COPY_INFO_HASH" ] || { COPY_ERROR="副本配置缺失或已改变"; return 1; }
    copy_signature || { COPY_ERROR="副本本地签名校验失败"; return 1; }
    copy_inspection="$(mktemp "$STATE_ROOT/.copy-inspection.XXXXXX")" || return 1
    remember_temp "$copy_inspection"
    /usr/bin/osascript -l JavaScript "$SCRIPT_DIR/inspect-macos-asar.js" "$COPY_PATH/Contents/Resources/app.asar" > "$copy_inspection" 2>> "$LOG_FILE" || return 1
    [ "$(json_get "$copy_inspection" languageGateStatus)" = local-copy-enabled ] || return 1
    [ "$(plist_value "$COPY_PATH/Contents/Info.plist" 'ElectronAsarIntegrity:Resources/app.asar:hash')" = "$(json_get "$copy_inspection" headerSha256)" ] || return 1
    COPY_QUARANTINED=false
    /usr/bin/xattr -p com.apple.quarantine "$COPY_PATH" >/dev/null 2>&1 && COPY_QUARANTINED=true
    COPY_VALID=true
    return 0
}

prepare_copy() {
    STAGE="copy-space"
    [ "$LANGUAGE_GATE_STATUS" = remote-dependent ] || { FAILURE_MESSAGE="当前版本语言逻辑未识别，已停止；不会猜测修改程序。"; return 1; }
    mkdir -p "$STATE_ROOT/copies" || return 1
    [ ! -L "$STATE_ROOT/copies" ] || { FAILURE_MESSAGE="副本目录是符号链接，已停止"; return 1; }
    copy_size="$(/usr/bin/du -sk "$APP_PATH" | /usr/bin/awk '{print $1}')"
    copy_free="$(available_kb "$STATE_ROOT")"
    case "$copy_size" in ''|*[!0-9]*) FAILURE_MESSAGE="无法读取应用大小"; return 1 ;; esac
    case "$copy_free" in ''|*[!0-9]*) FAILURE_MESSAGE="无法读取剩余空间"; return 1 ;; esac
    [ "$copy_free" -gt "$((copy_size + 262144))" ] || { FAILURE_MESSAGE="空间不足：需要应用副本大小外加 256 MB，未开始复制"; return 1; }
    copy_parent="$(mktemp -d "$STATE_ROOT/copies/copy.XXXXXX")" || return 1
    # Deliberately retained on interruption/failure. Never added to TEMP_PATHS.
    COPY_PATH="$copy_parent/Codex中文版.app"
    source_hash_before="$(asar_sha256)"
    COPY_SOURCE_HASH="$source_hash_before"
    source_info_before="$(copy_hash "$APP_PATH/Contents/Info.plist")"
    source_header_hash="$(plist_value "$APP_PATH/Contents/Info.plist" 'ElectronAsarIntegrity:Resources/app.asar:hash')"
    STAGE="copy-app"
    [ "${CODEX_ZH_TEST_FAIL_STAGE:-}" != copy ] || { FAILURE_MESSAGE="测试：应用复制失败"; return 1; }
    /usr/bin/ditto "$APP_PATH" "$COPY_PATH" >> "$LOG_FILE" 2>&1 || { FAILURE_MESSAGE="应用复制失败，未完成副本不会成为启动目标"; return 1; }
    STAGE="verify-copy"
    /usr/bin/diff -qr "$APP_PATH" "$COPY_PATH" >> "$LOG_FILE" 2>&1 || { FAILURE_MESSAGE="副本与官方文件不一致，已停止"; return 1; }
    copy_paths_confined || return 1
    [ ! "$COPY_PATH/Contents/Resources/app.asar" -ef "$APP_PATH/Contents/Resources/app.asar" ] || return 1
    STAGE="patch-copy-language"
    patch_result="$(mktemp "$STATE_ROOT/.patch-result.XXXXXX")" || return 1
    remember_temp "$patch_result"
    /usr/bin/osascript -l JavaScript "$SCRIPT_DIR/inspect-macos-asar.js" "$COPY_PATH/Contents/Resources/app.asar" --patch-copy "$APP_PATH/Contents/Resources/app.asar" "$COPY_PATH" "$COPY_SOURCE_HASH" > "$patch_result" 2>> "$LOG_FILE" || {
        FAILURE_MESSAGE="副本中文兼容处理失败，官方应用未改动"; return 1;
    }
    copy_plist="$COPY_PATH/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :ElectronAsarIntegrity' "$copy_plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity dict' "$copy_plist" &&
    /usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity:Resources/app.asar dict' "$copy_plist" &&
    /usr/libexec/PlistBuddy -c 'Add :ElectronAsarIntegrity:Resources/app.asar:algorithm string SHA256' "$copy_plist" &&
    /usr/libexec/PlistBuddy -c "Add :ElectronAsarIntegrity:Resources/app.asar:hash string $(json_get "$patch_result" headerSha256)" "$copy_plist" || return 1
    # Avoid confusing Dock/Launch Services with the untouched official app.
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.codex.zh-cn' "$copy_plist" || return 1
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleDisplayName' "$copy_plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Codex中文版' "$copy_plist" || return 1
    for update_key in SUEnableAutomaticChecks SUAutomaticallyUpdate; do
        /usr/libexec/PlistBuddy -c "Delete :$update_key" "$copy_plist" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Add :$update_key bool false" "$copy_plist" || return 1
    done
    STAGE="sign-copy"
    copy_paths_confined || return 1
    if [ "${CODEX_ZH_TESTING:-0}" != 1 ] || [ "${CODEX_ZH_TEST_REAL_SIGNING:-0}" = 1 ]; then
        copy_framework="$COPY_PATH/Contents/Frameworks/Codex Framework.framework"
        source_framework="$APP_PATH/Contents/Frameworks/Codex Framework.framework/Versions/Current/Codex Framework"
        /usr/bin/osascript -l JavaScript "$SCRIPT_DIR/macos-integrity.js" "$copy_framework/Versions/Current/Codex Framework" "$source_header_hash" "$(json_get "$patch_result" headerSha256)" "$COPY_PATH" "$source_framework" "$(copy_hash "$source_framework")" >> "$LOG_FILE" 2>&1 || {
            FAILURE_MESSAGE="新版 Electron 内嵌资源校验不支持，已停止且未激活副本"; return 1;
        }
        # Helpers load this framework too; mixed OpenAI/local signatures cannot do so.
        for helper_app in "$copy_framework/Versions/Current/Helpers/"*.app; do
            [ -d "$helper_app" ] || { FAILURE_MESSAGE="副本缺少 Electron 子程序"; return 1; }
            /usr/bin/codesign --force --sign - --options runtime --entitlements "$SCRIPT_DIR/macos-local.entitlements.plist" "$helper_app" >> "$LOG_FILE" 2>&1 || return 1
        done
        /usr/bin/codesign --force --sign - --options runtime "$copy_framework" >> "$LOG_FILE" 2>&1 || return 1
        # Do not claim OpenAI's team, push, shared keychain or application-group rights.
        /usr/bin/codesign --force --sign - --options runtime --entitlements "$SCRIPT_DIR/macos-local.entitlements.plist" "$COPY_PATH" >> "$LOG_FILE" 2>&1 || {
            FAILURE_MESSAGE="副本本地签名失败，未激活；不会关闭 macOS 安全保护"; return 1;
        }
    fi
    STAGE="verify-copy-signature"
    COPY_ASAR_HASH="$(copy_hash "$COPY_PATH/Contents/Resources/app.asar")"
    COPY_INFO_HASH="$(copy_hash "$copy_plist")"
    validate_copy || { FAILURE_MESSAGE="副本复核失败：$COPY_ERROR"; return 1; }
    [ "$(asar_sha256)" = "$source_hash_before" ] && [ "$(copy_hash "$APP_PATH/Contents/Info.plist")" = "$source_info_before" ] || {
        FAILURE_MESSAGE="官方应用在复制期间发生变化，未激活副本，请重新安装"; return 1;
    }
    COPY_ACTIVATED=false
    ok "独立中文副本已准备；本地签名不等于官方签名或 Apple 公证"
}

load_copy_state() {
    [ "$(json_get "$ACTIVE_STATE_PATH" copySchemaVersion)" = 3 ] || { STATE_VALID=false; return 1; }
    COPY_PATH="$(json_get "$ACTIVE_STATE_PATH" copyPath)"
    COPY_ASAR_HASH="$(json_get "$ACTIVE_STATE_PATH" copyAsarSha256)"
    COPY_INFO_HASH="$(json_get "$ACTIVE_STATE_PATH" copyInfoSha256)"
    COPY_SOURCE_HASH="$(json_get "$ACTIVE_STATE_PATH" asarSha256)"
    COPY_ACTIVATED="$(json_bool "$(json_get "$ACTIVE_STATE_PATH" copyActivated)")"
    validate_copy || { STATE_VALID=false; COPY_ACTIVATED=false; }
}

block_failed_copy() {
    case "$COPY_PATH" in "$STATE_ROOT"/copies/copy.*/Codex中文版.app) ;; *) return 1 ;; esac
    [ "$(dirname "$(dirname "$COPY_PATH")")" = "$STATE_ROOT/copies" ] || return 1
    [ ! -L "$(dirname "$COPY_PATH")" ] && [ ! -L "$STATE_ROOT/copies" ] || return 1
    printf '%s\n' 'launch-copy failed; rerun installer before launch' > "$(dirname "$COPY_PATH")/launch-failed" || return 1
    COPY_ACTIVATED=false; COPY_VALID=false; STATE_VALID=false; INSTALLATION_READY=false
}

copy_running() {
    [ -n "$COPY_PATH" ] || return 1
    copy_executable_dir="$(cd "$COPY_PATH/Contents/MacOS" 2>/dev/null && pwd -P)" || return 1
    /bin/ps -axo comm= | LC_ALL=C grep -F -x -q "$copy_executable_dir/$(plist_value "$COPY_PATH/Contents/Info.plist" CFBundleExecutable)"
}

quit_copy() {
    STAGE="stop-running-copy"
    validate_copy || { FAILURE_MESSAGE="无法安全识别要退出的副本，请保存任务并手动退出"; return 1; }
    if [ "${CODEX_ZH_TESTING:-0}" = 1 ]; then
        [ -z "${CODEX_ZH_TEST_QUIT_LOG:-}" ] || printf '%s\n' "$COPY_PATH" >> "$CODEX_ZH_TEST_QUIT_LOG"
        return 0
    fi
    copy_running || return 0
    copy_main="$copy_executable_dir/$(plist_value "$COPY_PATH/Contents/Info.plist" CFBundleExecutable)"
    copy_pids="$(/bin/ps -axo pid=,comm= | /usr/bin/awk -v target="$copy_main" '{pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == target) print pid}')"
    for copy_pid in $copy_pids; do
        # Recheck the exact executable immediately before sending a polite TERM.
        [ "$( /bin/ps -p "$copy_pid" -o comm=)" = "$copy_main" ] || continue
        /bin/kill -TERM "$copy_pid" || return 1
    done
    copy_waited=0
    while copy_running && [ "$copy_waited" -lt 30 ]; do sleep 1; copy_waited=$((copy_waited + 1)); done
    if copy_running; then FAILURE_MESSAGE="副本仍在运行，未强制结束；请保存任务并手动退出"; return 1; fi
}

open_copy() {
    STAGE="launch-copy"
    LAUNCH_ATTEMPTED=true
    validate_copy || { FAILURE_MESSAGE="副本启动前校验失败：$COPY_ERROR"; return 1; }
    if [ "${CODEX_ZH_TESTING:-0}" = 1 ]; then
        [ "${CODEX_ZH_TEST_OPEN_FAIL:-0}" != 1 ] || { FAILURE_MESSAGE="测试：副本启动失败"; return 1; }
        [ -z "${CODEX_ZH_TEST_OPEN_LOG:-}" ] || printf '%s\n' "$COPY_PATH" >> "$CODEX_ZH_TEST_OPEN_LOG"
        if [ "${CODEX_ZH_TEST_COPY_WAIT_FOR_SIGNAL:-0}" = 1 ]; then
            [ -z "${CODEX_ZH_TEST_SIGNAL_READY:-}" ] || printf '%s\n' ready > "$CODEX_ZH_TEST_SIGNAL_READY"
            while :; do sleep 1; done
        fi
    elif ! copy_running; then
        # Distinct cache/single-instance lock; original CODEX_HOME keeps conversations.
        # No xattr removal, spctl bypass, forced quit or direct executable launch.
        /usr/bin/open -n --env "CODEX_HOME=$CODEX_HOME" --env "CODEX_ELECTRON_USER_DATA_PATH=$STATE_ROOT/copy-user-data" "$COPY_PATH" --args "--user-data-dir=$STATE_ROOT/copy-user-data" >> "$LOG_FILE" 2>&1 || {
            FAILURE_MESSAGE="macOS 拒绝打开本地副本；请查看系统提示和问题报告，未关闭安全保护"; return 1;
        }
        copy_waited=0
        while [ "$copy_waited" -lt 20 ]; do
            copy_running && break
            sleep 1; copy_waited=$((copy_waited + 1))
        done
        copy_running || { FAILURE_MESSAGE="副本未启动或已退出，未激活；请把报告交给助教"; return 1; }
        # Catch delayed renderer/code-signature crashes, not just a short-lived PID.
        copy_stable=0
        while [ "$copy_stable" -lt 15 ]; do
            sleep 1
            copy_running || { FAILURE_MESSAGE="副本启动后退出，未激活；请把报告交给助教"; return 1; }
            copy_stable=$((copy_stable + 1))
        done
    fi
    PROGRAM_RUNNING=true
    COPY_ACTIVATED=true
    write_active_state copy || { STAGE="launch-copy"; COPY_ACTIVATED=false; FAILURE_MESSAGE="副本启动状态保存失败"; return 1; }
}
