#!/bin/bash

# Codex Desktop macOS 中文支持工具。
# 只使用 macOS 自带命令；不修改官方 App，不读取或记录配置中的私人内容。

set -u

TOOL_VERSION="0.2.0-preview.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=macos-copy.sh
source "$SCRIPT_DIR/macos-copy.sh" || exit 1
BUNDLE_ID="com.openai.codex"
EXPECTED_TEAM_ID="2DC432GLL2"
ACTION="install"
NO_RESTART=1
JSON_OUTPUT=0
APP_OVERRIDE=""
CODEX_HOME_OVERRIDE=""
STATE_ROOT_OVERRIDE=""
UI_RESULT=""
NATIVE_UI_ENGLISH_CONFIRMED=false

STAGE="startup"
FAILURE_MESSAGE=""
LAUNCH_ATTEMPTED=false
APP_PATH=""
APP_EXECUTABLE=""
APP_VERSION=""
BUILD_VERSION=""
APP_ARCHITECTURES=""
MACHINE_ARCH="${CODEX_ZH_TEST_MACHINE_ARCH:-$(uname -m 2>/dev/null || printf 'unknown')}"
MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
SIGNATURE_VALID=false
NOTARIZATION_ACCEPTED=false
RESOURCES_READY=false
NATIVE_MENU_ZH=false
WEBVIEW_ZH=false
LOCALE_OVERRIDE_SUPPORTED=false
NATIVE_INTL_SUPPORTED=false
ARCHITECTURE_COMPATIBLE=false
STATE_VALID=false
SOURCE_CHANGED=false
INSTALLATION_READY=false
SETTINGS_PREPARED=false
LANGUAGE_GATE_DETECTED=false
LANGUAGE_GATE_STATUS="unknown"
GATE_EVIDENCE="[]"
RESOURCE_CHECK_ERROR=""
TOOL_ISSUE_SUSPECTED=false
PROBLEM_CLASSIFICATION="none"
PROGRAM_RUNNING=false
UI_LANGUAGE_VERIFIED=false
UI_VERIFICATION_STATUS="pending-user-check"
CURRENT_LOCALE=""
NEXT_ACTION="check-codex-installation"
LAST_RESULT="checking"
LOG_FILE=""
REPORT_FILE=""
CONFIG_PATH=""
STATE_ROOT=""
ACTIVE_STATE_PATH=""
TEMP_PATHS=("")
LAST_BACKUP_PATH=""
LAST_CONFIG_ORIGINAL=0
LAST_STATE_BACKUP_PATH=""
LAST_STATE_ORIGINAL=0
TRANSACTION_ACTIVE=0
REPORTING_READY=false

usage() {
    cat <<'EOF'
用法：install_macos.sh [选项]

  --action install   安装/更新中文设置（默认）
  --action status    检查状态并生成问题报告
  --action open      校验后打开中文版
  --action restore   恢复英文，不删除备份和用户数据
  --no-restart       不退出当前 Codex（默认，适合让 Codex 中的 AI 执行）
  --restart          安装或恢复后退出并重新打开 Codex
  --json             状态检查只输出 JSON
  --mode auto|native|copy
                     自动选择（默认）；只用官方设置；独立中文兼容副本
  --ui-result english|chinese
                     检查状态时记录用户亲眼看到的菜单和主界面结果
  --app PATH         手动指定 Codex.app 或 ChatGPT.app
  --codex-home PATH  手动指定 Codex 数据目录
  --help              显示帮助
EOF
}

log_line() {
    level="$1"
    shift
    message="$*"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    if [ -n "$LOG_FILE" ]; then
        printf '%s [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
    if [ "$JSON_OUTPUT" -eq 1 ]; then
        printf '[%s] %s\n' "$level" "$message" >&2
    else
        printf '[%s] %s\n' "$level" "$message"
    fi
}

info() { log_line "信息" "$@"; }
ok() { log_line "成功" "$@"; }
warn() { log_line "提醒" "$@"; }

cleanup() {
    for path in "${TEMP_PATHS[@]}"; do
        if [ -n "$path" ] && [ -e "$path" ]; then rm -rf -- "$path" 2>/dev/null || true; fi
    done
}

remember_temp() {
    TEMP_PATHS[${#TEMP_PATHS[@]}]="$1"
}

display_path() {
    case "$1" in
        "$HOME") printf '~' ;;
        "$HOME"/*) printf '%s/%s' '~' "${1#"$HOME"/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

plist_value() {
    plist="$1"
    key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

json_get() {
    json_path="$1"
    key="$2"
    /usr/bin/plutil -extract "$key" raw -o - "$json_path" 2>/dev/null || true
}

json_bool() {
    if [ "$1" = "true" ] || [ "$1" = "1" ]; then printf 'true'; else printf 'false'; fi
}

json_insert_string() {
    file="$1"; key="$2"; value="$3"
    /usr/bin/plutil -insert "$key" -string "$value" "$file"
}

json_insert_bool() {
    file="$1"; key="$2"; value="$3"
    if [ "$value" = "true" ]; then
        /usr/bin/plutil -insert "$key" -bool YES "$file"
    else
        /usr/bin/plutil -insert "$key" -bool NO "$file"
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --action)
                [ "$#" -ge 2 ] || { printf '缺少 --action 参数\n' >&2; exit 2; }
                ACTION="$2"; shift 2 ;;
            --no-restart) NO_RESTART=1; shift ;;
            --restart) NO_RESTART=0; shift ;;
            --json) JSON_OUTPUT=1; shift ;;
            --mode)
                [ "$#" -ge 2 ] || { printf '缺少 --mode 参数\n' >&2; exit 2; }
                INSTALL_MODE="$2"; shift 2 ;;
            --ui-result)
                [ "$#" -ge 2 ] || { printf '缺少 --ui-result 参数\n' >&2; exit 2; }
                UI_RESULT="$2"; shift 2 ;;
            --app)
                [ "$#" -ge 2 ] || { printf '缺少 --app 路径\n' >&2; exit 2; }
                APP_OVERRIDE="$2"; shift 2 ;;
            --codex-home)
                [ "$#" -ge 2 ] || { printf '缺少 --codex-home 路径\n' >&2; exit 2; }
                CODEX_HOME_OVERRIDE="$2"; shift 2 ;;
            --state-root)
                [ "$#" -ge 2 ] || { printf '缺少 --state-root 路径\n' >&2; exit 2; }
                STATE_ROOT_OVERRIDE="$2"; shift 2 ;;
            --help|-h) usage; exit 0 ;;
            *) printf '未知参数：%s\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
    done
    case "$ACTION" in install|status|open|restore) ;; *) printf '不支持的操作：%s\n' "$ACTION" >&2; exit 2 ;; esac
    case "$INSTALL_MODE" in auto|native|copy) ;; *) printf '不支持的模式：%s\n' "$INSTALL_MODE" >&2; exit 2 ;; esac
    if [ -n "$UI_RESULT" ]; then
        case "$UI_RESULT" in english|chinese) ;; *) printf '界面结果只支持 english 或 chinese\n' >&2; exit 2 ;; esac
        [ "$ACTION" = status ] || { printf '--ui-result 只能与 --action status 一起使用\n' >&2; exit 2; }
    fi
}

activate_fallback_reporting() {
    fallback_parent="${TMPDIR:-/tmp}"
    fallback_root="$(mktemp -d "$fallback_parent/codex-zh-macos-report.XXXXXX" 2>/dev/null)" || return 1
    chmod 700 "$fallback_root" 2>/dev/null || true
    STATE_ROOT="$fallback_root"
    ACTIVE_STATE_PATH="$STATE_ROOT/active-state.json"
    mkdir -p -- "$STATE_ROOT/logs" "$STATE_ROOT/diagnostics" || return 1
    stamp="$(date '+%Y%m%d-%H%M%S')-$$"
    LOG_FILE="$STATE_ROOT/logs/$ACTION-$stamp.log"
    REPORT_FILE="$STATE_ROOT/diagnostics/report-$stamp.json"
    : > "$LOG_FILE" || return 1
    REPORTING_READY=true
    return 0
}

init_paths() {
    if [ -n "$CODEX_HOME_OVERRIDE" ]; then
        CODEX_HOME="$CODEX_HOME_OVERRIDE"
    elif [ -z "${CODEX_HOME:-}" ]; then
        CODEX_HOME="$HOME/.codex"
    fi
    CONFIG_PATH="$CODEX_HOME/config.toml"
    if [ -n "$STATE_ROOT_OVERRIDE" ]; then
        STATE_ROOT="$STATE_ROOT_OVERRIDE"
    else
        STATE_ROOT="$CODEX_HOME/zh-cn-tool/macos"
    fi
    ACTIVE_STATE_PATH="$STATE_ROOT/active-state.json"
    requested_state_root="$STATE_ROOT"
    if ! mkdir -p -- "$STATE_ROOT/logs" "$STATE_ROOT/diagnostics" "$STATE_ROOT/backups" 2>/dev/null; then
        STAGE="init-state-directory"
        FAILURE_MESSAGE="无法创建工具状态目录：$(display_path "$requested_state_root")"
        activate_fallback_reporting || {
            printf '%s；临时问题报告目录也无法创建。\n' "$FAILURE_MESSAGE" >&2
            return 1
        }
        printf '%s；问题报告将临时保存在：%s\n' "$FAILURE_MESSAGE" "$REPORT_FILE" >&2
        return 1
    fi
    stamp="$(date '+%Y%m%d-%H%M%S')-$$"
    LOG_FILE="$STATE_ROOT/logs/$ACTION-$stamp.log"
    REPORT_FILE="$STATE_ROOT/diagnostics/report-$stamp.json"
    if ! : > "$LOG_FILE"; then
        STAGE="init-log-file"
        FAILURE_MESSAGE="无法写入日志：$(display_path "$LOG_FILE")"
        activate_fallback_reporting || {
            printf '%s；临时问题报告目录也无法创建。\n' "$FAILURE_MESSAGE" >&2
            return 1
        }
        printf '%s；问题报告将临时保存在：%s\n' "$FAILURE_MESSAGE" "$REPORT_FILE" >&2
        return 1
    fi
    REPORTING_READY=true
}

find_app() {
    STAGE="discover-app"
    candidates=""
    if [ -n "$APP_OVERRIDE" ]; then candidates="$APP_OVERRIDE"; fi
    if [ -n "${CODEX_MAC_APP:-}" ]; then candidates="$candidates
$CODEX_MAC_APP"; fi
    candidates="$candidates
/Applications/Codex.app
/Applications/ChatGPT.app
$HOME/Applications/Codex.app
$HOME/Applications/ChatGPT.app"
    old_ifs="$IFS"
    IFS='
'
    for candidate in $candidates; do
        [ -n "$candidate" ] || continue
        if [ -d "$candidate/Contents" ]; then
            bundle_id="$(plist_value "$candidate/Contents/Info.plist" CFBundleIdentifier)"
            if [ "$bundle_id" = "$BUNDLE_ID" ]; then APP_PATH="$candidate"; break; fi
        fi
    done
    IFS="$old_ifs"
    if [ -z "$APP_PATH" ] && command -v mdfind >/dev/null 2>&1; then
        candidate="$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | head -n 1)"
        if [ -d "$candidate/Contents" ]; then APP_PATH="$candidate"; fi
    fi
    [ -n "$APP_PATH" ] || return 1
    plist="$APP_PATH/Contents/Info.plist"
    executable_name="$(plist_value "$plist" CFBundleExecutable)"
    APP_VERSION="$(plist_value "$plist" CFBundleShortVersionString)"
    BUILD_VERSION="$(plist_value "$plist" CFBundleVersion)"
    APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$executable_name"
    [ -f "$APP_EXECUTABLE" ] || return 1
    return 0
}

detect_architectures() {
    if [ -n "${CODEX_ZH_TEST_ARCH:-}" ]; then
        APP_ARCHITECTURES="$CODEX_ZH_TEST_ARCH"
    else
        APP_ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_EXECUTABLE" 2>/dev/null || true)"
        if [ -z "$APP_ARCHITECTURES" ]; then
            APP_ARCHITECTURES="$(file "$APP_EXECUTABLE" 2>/dev/null | sed -n 's/.*Mach-O[^ ]* executable //p')"
        fi
        [ -n "$APP_ARCHITECTURES" ] || APP_ARCHITECTURES="unknown"
    fi
    case " $APP_ARCHITECTURES " in
        *" $MACHINE_ARCH "*) ARCHITECTURE_COMPATIBLE=true ;;
        *) ARCHITECTURE_COMPATIBLE=false ;;
    esac
}

verify_signature() {
    STAGE="verify-signature"
    if [ "${CODEX_ZH_TESTING:-0}" = "1" ]; then
        SIGNATURE_VALID="$(json_bool "${CODEX_ZH_TEST_SIGNATURE_VALID:-true}")"
        NOTARIZATION_ACCEPTED="$(json_bool "${CODEX_ZH_TEST_NOTARIZED:-true}")"
        return 0
    fi
    if /usr/bin/codesign --verify --deep --strict "$APP_PATH" >> "$LOG_FILE" 2>&1; then
        signature_text="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
        team_id="$(printf '%s\n' "$signature_text" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
        identifier="$(printf '%s\n' "$signature_text" | sed -n 's/^Identifier=//p' | head -n 1)"
        if [ "$team_id" = "$EXPECTED_TEAM_ID" ] && [ "$identifier" = "$BUNDLE_ID" ]; then SIGNATURE_VALID=true; fi
    fi
    if /usr/sbin/spctl --assess --type execute "$APP_PATH" >> "$LOG_FILE" 2>&1; then NOTARIZATION_ACCEPTED=true; fi
    [ "$SIGNATURE_VALID" = true ] && [ "$NOTARIZATION_ACCEPTED" = true ]
}

check_resources() {
    STAGE="check-resources"
    asar="$APP_PATH/Contents/Resources/app.asar"
    [ -f "$asar" ] || return 1
    inspection_file="$(mktemp "$STATE_ROOT/.asar-inspection.XXXXXX")" || return 1
    inspection_error="$(mktemp "$STATE_ROOT/.asar-error.XXXXXX")" || return 1
    remember_temp "$inspection_file"; remember_temp "$inspection_error"
    if ! /usr/bin/osascript -l JavaScript "$SCRIPT_DIR/inspect-macos-asar.js" "$asar" > "$inspection_file" 2> "$inspection_error"; then
        RESOURCE_CHECK_ERROR="$(head -c 1500 "$inspection_error" | sed 's/^.*execution error: //')"
        return 1
    fi
    [ "$(json_get "$inspection_file" resourcesReady)" = true ] || return 1
    LANGUAGE_GATE_DETECTED="$(json_bool "$(json_get "$inspection_file" languageGateDetected)")"
    LANGUAGE_GATE_STATUS="$(json_get "$inspection_file" languageGateStatus)"
    GATE_EVIDENCE="$(/usr/bin/plutil -extract gateEvidence json -o - "$inspection_file" 2>/dev/null || printf '[]')"
    expected_header_hash="$(plist_value "$APP_PATH/Contents/Info.plist" 'ElectronAsarIntegrity:Resources/app.asar:hash')"
    if [ -n "$expected_header_hash" ] && [ "$expected_header_hash" != "$(json_get "$inspection_file" headerSha256)" ]; then
        RESOURCE_CHECK_ERROR="Info.plist 与 ASAR 文件头 SHA-256 不一致"
        return 1
    fi
    NATIVE_MENU_ZH=true; WEBVIEW_ZH=true; LOCALE_OVERRIDE_SUPPORTED=true; NATIVE_INTL_SUPPORTED=true
    RESOURCES_READY=true
    return 0
}

get_locale() {
    [ -f "$CONFIG_PATH" ] || { printf ''; return; }
    validate_config_shape || { printf ''; return; }
    /usr/bin/awk '
        BEGIN { inDesktop=0; found=0 }
        /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
            inDesktop = ($0 ~ /^[[:space:]]*\[desktop\][[:space:]]*(#.*)?$/)
            next
        }
        inDesktop && /^[[:space:]]*localeOverride[[:space:]]*=/ {
            line=$0
            sub(/^[^=]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]*(#.*)?$/, "", line)
            gsub(/^\"|\"$/, "", line)
            print line
            found++
        }
        END { if (found > 1) exit 9 }
    ' "$CONFIG_PATH" 2>/dev/null | tail -n 1
}

validate_config_shape() {
    [ -f "$CONFIG_PATH" ] || return 0
    /usr/bin/awk '
        BEGIN { desktop=0; locale=0; complex=0; inDesktop=0 }
        {
            compact=$0
            gsub(/[[:space:]]/, "", compact)
            if (index($0, "\"\"\"") || index($0, "\047\047\047")) complex++
            if (compact ~ /^desktop\./ || compact ~ /^\"desktop\"\./ || compact ~ /^\047desktop\047\./) complex++
            if (compact ~ /^desktop=\{/ || compact ~ /^\"desktop\"=\{/ || compact ~ /^\047desktop\047=\{/) complex++
            if (compact ~ /^\[\"desktop\"\]/ || compact ~ /^\[\047desktop\047\]/ || compact ~ /^\[\[desktop\]\]/) complex++
            if (compact ~ /^\[desktop\](#.*)?$/ && $0 !~ /^[[:space:]]*\[desktop\][[:space:]]*(#.*)?$/) complex++
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
            inDesktop = ($0 ~ /^[[:space:]]*\[desktop\][[:space:]]*(#.*)?$/)
            if (inDesktop) desktop++
            next
        }
        inDesktop && /^[[:space:]]*localeOverride[[:space:]]*=/ { locale++ }
        inDesktop && /^[[:space:]]*["\047]localeOverride["\047][[:space:]]*=/ { complex++ }
        END { if (desktop > 1 || locale > 1 || complex > 0) exit 1 }
    ' "$CONFIG_PATH"
}

available_kb() {
    target="$1"
    if [ -n "${CODEX_ZH_TEST_FREE_KB:-}" ]; then printf '%s' "$CODEX_ZH_TEST_FREE_KB"; return; fi
    /bin/df -Pk "$target" 2>/dev/null | /usr/bin/awk 'NR==2 {print $4}'
}

write_locale_transaction() {
    desired="$1"
    STAGE="backup-config"
    mkdir -p -- "$CODEX_HOME" || return 1
    free_kb="$(available_kb "$CODEX_HOME")"
    case "$free_kb" in ''|*[!0-9]*) FAILURE_MESSAGE="无法读取配置目录剩余空间"; return 1 ;; esac
    if [ "$free_kb" -lt 1024 ]; then FAILURE_MESSAGE="配置目录剩余空间不足 1 MB"; return 1; fi
    validate_config_shape || { FAILURE_MESSAGE="config.toml 使用了重复或复杂 TOML 写法，工具无法保证安全修改，已停止且未改动配置"; return 1; }

    backup_path=""
    original_existed=0
    if [ -f "$CONFIG_PATH" ]; then
        original_existed=1
        backup_path="$STATE_ROOT/backups/config.toml.$(date '+%Y%m%d-%H%M%S')-$$.bak"
        if [ "${CODEX_ZH_TEST_FAIL_STAGE:-}" = "backup" ]; then FAILURE_MESSAGE="测试：配置备份复制失败"; return 1; fi
        /bin/cp -p -- "$CONFIG_PATH" "$backup_path" || { FAILURE_MESSAGE="无法备份 config.toml"; return 1; }
    fi
    LAST_BACKUP_PATH="$backup_path"
    LAST_CONFIG_ORIGINAL="$original_existed"

    state_backup_path=""
    state_original_existed=0
    if [ -f "$ACTIVE_STATE_PATH" ]; then
        state_original_existed=1
        state_backup_path="$STATE_ROOT/backups/active-state.$(date '+%Y%m%d-%H%M%S')-$$.json.bak"
        /bin/cp -p -- "$ACTIVE_STATE_PATH" "$state_backup_path" || { FAILURE_MESSAGE="无法备份当前安装状态"; return 1; }
    fi
    LAST_STATE_BACKUP_PATH="$state_backup_path"
    LAST_STATE_ORIGINAL="$state_original_existed"

    config_tmp="$(mktemp "$CODEX_HOME/.config.toml.XXXXXX")" || { FAILURE_MESSAGE="无法创建临时配置"; return 1; }
    remember_temp "$config_tmp"
    source_config="$CONFIG_PATH"
    if [ ! -f "$source_config" ]; then source_config="/dev/null"; fi
    STAGE="write-locale"
    /usr/bin/awk -v value="$desired" '
        BEGIN { inDesktop=0; desktopSeen=0; localeSeen=0; printed=0 }
        function emitLocale() { print "localeOverride = \"" value "\""; localeSeen=1 }
        /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
            if (inDesktop && !localeSeen) emitLocale()
            inDesktop = ($0 ~ /^[[:space:]]*\[desktop\][[:space:]]*(#.*)?$/)
            if (inDesktop) desktopSeen=1
            print
            next
        }
        inDesktop && /^[[:space:]]*localeOverride[[:space:]]*=/ {
            if (!localeSeen) emitLocale()
            next
        }
        { print }
        END {
            if (inDesktop && !localeSeen) emitLocale()
            if (!desktopSeen) {
                if (NR > 0) print ""
                print "[desktop]"
                emitLocale()
            }
        }
    ' "$source_config" > "$config_tmp" || { FAILURE_MESSAGE="无法生成新配置"; return 1; }
    chmod 600 "$config_tmp" 2>/dev/null || true
    if [ "${CODEX_ZH_TEST_FAIL_STAGE:-}" = "config" ]; then FAILURE_MESSAGE="测试：配置写入中断"; return 1; fi
    TRANSACTION_ACTIVE=1
    /bin/mv -f -- "$config_tmp" "$CONFIG_PATH" || {
        FAILURE_MESSAGE="无法原子替换 config.toml"
        rollback_transaction || FAILURE_MESSAGE="${FAILURE_MESSAGE}，且自动回滚失败"
        return 1
    }

    CURRENT_LOCALE="$(get_locale)"
    if [ "$CURRENT_LOCALE" != "$desired" ]; then
        FAILURE_MESSAGE="语言配置写入后回读不一致"
        rollback_transaction || FAILURE_MESSAGE="${FAILURE_MESSAGE}，且自动回滚失败"
        return 1
    fi

    if [ "${CODEX_ZH_TEST_WAIT_FOR_SIGNAL:-0}" = "1" ]; then
        while :; do :; done
    fi

    if [ "${CODEX_ZH_TEST_FAIL_STAGE:-}" = "state" ]; then
        FAILURE_MESSAGE="测试：状态文件写入中断"
        rollback_transaction || FAILURE_MESSAGE="${FAILURE_MESSAGE}，且自动回滚失败"
        return 1
    fi
    return 0
}

rollback_config() {
    backup_path="$1"
    original_existed="$2"
    if [ "$original_existed" -eq 1 ]; then
        [ -f "$backup_path" ] || return 1
        /bin/cp -p -- "$backup_path" "$CONFIG_PATH" 2>/dev/null
    elif [ "$original_existed" -eq 0 ] && [ -f "$CONFIG_PATH" ]; then
        /bin/rm -f -- "$CONFIG_PATH" 2>/dev/null
    fi
}

rollback_transaction() {
    [ "$TRANSACTION_ACTIVE" -eq 1 ] || return 0
    rollback_status=0
    rollback_config "$LAST_BACKUP_PATH" "$LAST_CONFIG_ORIGINAL" || rollback_status=1
    if [ "$LAST_STATE_ORIGINAL" -eq 1 ] && [ -f "$LAST_STATE_BACKUP_PATH" ]; then
        /bin/cp -p -- "$LAST_STATE_BACKUP_PATH" "$ACTIVE_STATE_PATH" 2>/dev/null || rollback_status=1
    elif [ "$LAST_STATE_ORIGINAL" -eq 0 ] && [ -f "$ACTIVE_STATE_PATH" ]; then
        /bin/rm -f -- "$ACTIVE_STATE_PATH" 2>/dev/null || rollback_status=1
    fi
    TRANSACTION_ACTIVE=0
    return "$rollback_status"
}

commit_transaction() {
    TRANSACTION_ACTIVE=0
}

asar_sha256() {
    /usr/bin/shasum -a 256 "$APP_PATH/Contents/Resources/app.asar" 2>/dev/null | /usr/bin/awk '{print $1}'
}

write_active_state() {
    mode="$1"
    STAGE="write-state"
    state_tmp_dir="$(mktemp -d "$STATE_ROOT/.active-state.XXXXXX")" || return 1
    remember_temp "$state_tmp_dir"
    state_tmp="$state_tmp_dir/active-state.json"
    /usr/bin/plutil -create xml1 "$state_tmp" || return 1
    json_insert_string "$state_tmp" toolVersion "$TOOL_VERSION"
    json_insert_string "$state_tmp" updatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    json_insert_string "$state_tmp" mode "$mode"
    json_insert_string "$state_tmp" appPath "$APP_PATH"
    json_insert_string "$state_tmp" bundleIdentifier "$BUNDLE_ID"
    json_insert_string "$state_tmp" codexVersion "$APP_VERSION"
    json_insert_string "$state_tmp" buildVersion "$BUILD_VERSION"
    json_insert_string "$state_tmp" appArchitectures "$APP_ARCHITECTURES"
    if [ "$mode" = copy ]; then
        json_insert_string "$state_tmp" asarSha256 "$COPY_SOURCE_HASH"
    else
        json_insert_string "$state_tmp" asarSha256 "$(asar_sha256)"
    fi
    json_insert_string "$state_tmp" locale "$CURRENT_LOCALE"
    json_insert_bool "$state_tmp" resourcesReady "$RESOURCES_READY"
    json_insert_bool "$state_tmp" uiLanguageVerified false
    json_insert_bool "$state_tmp" nativeUiEnglishConfirmed "$NATIVE_UI_ENGLISH_CONFIRMED"
    if [ "$mode" = copy ]; then
        json_insert_string "$state_tmp" copySchemaVersion "3"
        json_insert_string "$state_tmp" copyPath "$COPY_PATH"
        json_insert_string "$state_tmp" copyAsarSha256 "$COPY_ASAR_HASH"
        json_insert_string "$state_tmp" copyInfoSha256 "$COPY_INFO_HASH"
        json_insert_bool "$state_tmp" copyActivated "$COPY_ACTIVATED"
    fi
    /usr/bin/plutil -convert json "$state_tmp" || return 1
    chmod 600 "$state_tmp" 2>/dev/null || true
    if [ -f "$ACTIVE_STATE_PATH" ]; then
        state_history="$(mktemp "$STATE_ROOT/backups/state-before.XXXXXX")" || return 1
        /bin/cp -p -- "$ACTIVE_STATE_PATH" "$state_history" || return 1
    fi
    /bin/mv -f -- "$state_tmp" "$ACTIVE_STATE_PATH"
}

load_state() {
    STATE_VALID=false
    SOURCE_CHANGED=false
    [ -f "$ACTIVE_STATE_PATH" ] || return 0
    state_bundle="$(json_get "$ACTIVE_STATE_PATH" bundleIdentifier)"
    state_app="$(json_get "$ACTIVE_STATE_PATH" appPath)"
    state_hash="$(json_get "$ACTIVE_STATE_PATH" asarSha256)"
    state_mode="$(json_get "$ACTIVE_STATE_PATH" mode)"
    case "$state_mode" in zh-CN|copy|english) ;; *) warn "状态记录的安装模式损坏，将忽略并允许重新安装。"; return 0 ;; esac
    if [ "$state_bundle" != "$BUNDLE_ID" ] || [ -z "$state_app" ] || [ -z "$state_hash" ]; then
        warn "发现损坏或旧版状态记录，将忽略它；重新安装可安全替换。"
        return 0
    fi
    if [ "$state_mode" = "english" ]; then return 0; fi
    if [ "$state_app" != "$APP_PATH" ] || [ "$state_hash" != "$(asar_sha256)" ] ||
       [ "$(json_get "$ACTIVE_STATE_PATH" codexVersion)" != "$APP_VERSION" ] ||
       [ "$(json_get "$ACTIVE_STATE_PATH" buildVersion)" != "$BUILD_VERSION" ]; then SOURCE_CHANGED=true; return 0; fi
    [ "$(json_get "$ACTIVE_STATE_PATH" toolVersion)" = "$TOOL_VERSION" ] || return 0
    STATE_VALID=true
    if [ "$state_mode" = zh-CN ]; then
        NATIVE_UI_ENGLISH_CONFIRMED="$(json_bool "$(json_get "$ACTIVE_STATE_PATH" nativeUiEnglishConfirmed)")"
    fi
    if [ "$state_mode" = copy ]; then EFFECTIVE_MODE=copy; load_copy_state; fi
}

is_program_running() {
    [ -n "$APP_EXECUTABLE" ] || return 1
    /bin/ps -axo comm= 2>/dev/null | LC_ALL=C grep -F -x -q "$APP_EXECUTABLE"
}

open_app() {
    STAGE="launch"
    LAUNCH_ATTEMPTED=true
    if [ "${CODEX_ZH_TESTING:-0}" = "1" ]; then
        if [ "${CODEX_ZH_TEST_OPEN_FAIL:-0}" = "1" ]; then FAILURE_MESSAGE="测试：Codex 启动失败"; return 1; fi
        if [ -n "${CODEX_ZH_TEST_OPEN_LOG:-}" ]; then printf '%s\n' "$APP_PATH" >> "$CODEX_ZH_TEST_OPEN_LOG"; fi
        PROGRAM_RUNNING=true
        return 0
    fi
    /usr/bin/open "$APP_PATH" || { FAILURE_MESSAGE="macOS 无法打开已校验的 Codex"; return 1; }
    waited=0
    while [ "$waited" -lt 20 ]; do
        if is_program_running; then PROGRAM_RUNNING=true; return 0; fi
        sleep 1
        waited=$((waited + 1))
    done
    FAILURE_MESSAGE="已发送启动请求，但 20 秒内没有检测到主进程"
    return 1
}

quit_app() {
    STAGE="stop-running-app"
    if ! is_program_running; then return 0; fi
    if [ "${CODEX_ZH_TESTING:-0}" = "1" ]; then PROGRAM_RUNNING=false; return 0; fi
    /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >> "$LOG_FILE" 2>&1 || return 1
    waited=0
    while [ "$waited" -lt 30 ]; do
        if ! is_program_running; then PROGRAM_RUNNING=false; return 0; fi
        sleep 1
        waited=$((waited + 1))
    done
    FAILURE_MESSAGE="Codex 仍在运行。工具没有强制结束它，请保存任务后手动退出。"
    return 1
}

inspect_all() {
    APP_PATH=""; APP_EXECUTABLE=""; APP_VERSION=""; BUILD_VERSION=""; APP_ARCHITECTURES=""
    SIGNATURE_VALID=false; NOTARIZATION_ACCEPTED=false; RESOURCES_READY=false
    NATIVE_MENU_ZH=false; WEBVIEW_ZH=false; LOCALE_OVERRIDE_SUPPORTED=false; NATIVE_INTL_SUPPORTED=false
    LANGUAGE_GATE_DETECTED=false; LANGUAGE_GATE_STATUS="unknown"; GATE_EVIDENCE="[]"; RESOURCE_CHECK_ERROR=""
    SETTINGS_PREPARED=false; INSTALLATION_READY=false; STATE_VALID=false; SOURCE_CHANGED=false
    EFFECTIVE_MODE=native; COPY_VALID=false; COPY_ACTIVATED=false; COPY_PATH=""
    NATIVE_UI_ENGLISH_CONFIRMED=false
    ARCHITECTURE_COMPATIBLE=false; PROGRAM_RUNNING=false
    if ! find_app; then return 1; fi
    detect_architectures
    verify_signature || true
    check_resources || true
    CURRENT_LOCALE="$(get_locale)"
    load_state
    if is_program_running; then PROGRAM_RUNNING=true; fi
    if [ "$CURRENT_LOCALE" = "zh-CN" ] && [ "$SIGNATURE_VALID" = true ] && [ "$NOTARIZATION_ACCEPTED" = true ] &&
       [ "$RESOURCES_READY" = true ] && [ "$ARCHITECTURE_COMPATIBLE" = true ] && [ "$STATE_VALID" = true ]; then
        SETTINGS_PREPARED=true
    else
        SETTINGS_PREPARED=false
    fi
    INSTALLATION_READY=false
    if [ "$EFFECTIVE_MODE" = copy ] && [ "$COPY_VALID" = true ] && [ "$SETTINGS_PREPARED" = true ]; then
        INSTALLATION_READY=true
        PROGRAM_RUNNING=false
        copy_running && PROGRAM_RUNNING=true
    fi
    # Neither finding a default nor failing to find a known gate proves runtime activation.
    # Only this check's explicit user confirmation can complete native-mode acceptance.
    return 0
}

calculate_next_action() {
    if [ -z "$APP_PATH" ]; then NEXT_ACTION="install-official-codex"
    elif [ "$SIGNATURE_VALID" != true ] || [ "$NOTARIZATION_ACCEPTED" != true ]; then NEXT_ACTION="reinstall-official-codex-from-trusted-source"
    elif [ "$ARCHITECTURE_COMPATIBLE" != true ]; then NEXT_ACTION="install-correct-codex-architecture"
    elif [ "$RESOURCES_READY" != true ]; then NEXT_ACTION="update-or-reinstall-official-codex"
    elif [ "$SOURCE_CHANGED" = true ]; then NEXT_ACTION="rerun-macos-installer-after-official-update"
    elif [ "$CURRENT_LOCALE" != "zh-CN" ]; then NEXT_ACTION="run-macos-installer"
    elif [ "$STATE_VALID" != true ]; then NEXT_ACTION="rerun-macos-installer"
    elif [ "$NATIVE_UI_ENGLISH_CONFIRMED" = true ] && [ "$EFFECTIVE_MODE" = native ] && [ "$SETTINGS_PREPARED" = true ]; then NEXT_ACTION="run-explicit-copy-fallback-after-native-ui-failure"
    elif [ "$UI_RESULT" = english ]; then NEXT_ACTION="send-ui-failure-report-to-tutor"
    elif [ "$LANGUAGE_GATE_STATUS" = "unrecognized" ]; then NEXT_ACTION="send-unsupported-language-logic-report-to-tutor"
    elif [ "$INSTALLATION_READY" != true ]; then NEXT_ACTION="verify-chinese-ui-or-report-language-gate"
    elif [ "$PROGRAM_RUNNING" = true ]; then NEXT_ACTION="check-chinese-ui"
    else NEXT_ACTION="open-chinese-codex-and-check-ui"
    fi
}

write_report() {
    report_result="$1"
    report_message="$2"
    calculate_next_action
    report_tmp_dir="$(mktemp -d "$STATE_ROOT/.report.XXXXXX")" || return 1
    remember_temp "$report_tmp_dir"
    report_tmp="$report_tmp_dir/report.json"
    /usr/bin/plutil -create xml1 "$report_tmp" || return 1
    json_insert_string "$report_tmp" toolVersion "$TOOL_VERSION"
    json_insert_string "$report_tmp" generatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    json_insert_string "$report_tmp" lastResult "$report_result"
    report_stage="$STAGE"
    if [ "$report_result" = "success" ]; then report_stage=""; fi
    json_insert_string "$report_tmp" failureStage "$report_stage"
    json_insert_string "$report_tmp" failureMessage "$report_message"
    json_insert_bool "$report_tmp" appFound "$([ -n "$APP_PATH" ] && printf true || printf false)"
    json_insert_string "$report_tmp" appPath "$(display_path "$APP_PATH")"
    json_insert_string "$report_tmp" bundleIdentifier "$BUNDLE_ID"
    json_insert_string "$report_tmp" codexVersion "$APP_VERSION"
    json_insert_string "$report_tmp" buildVersion "$BUILD_VERSION"
    json_insert_string "$report_tmp" macOSVersion "$MACOS_VERSION"
    json_insert_string "$report_tmp" machineArchitecture "$MACHINE_ARCH"
    json_insert_string "$report_tmp" appArchitectures "$APP_ARCHITECTURES"
    json_insert_bool "$report_tmp" architectureCompatible "$ARCHITECTURE_COMPATIBLE"
    json_insert_bool "$report_tmp" signatureValid "$SIGNATURE_VALID"
    json_insert_bool "$report_tmp" notarizationAccepted "$NOTARIZATION_ACCEPTED"
    json_insert_bool "$report_tmp" resourcesReady "$RESOURCES_READY"
    json_insert_bool "$report_tmp" nativeMenuZhCn "$NATIVE_MENU_ZH"
    json_insert_bool "$report_tmp" webviewZhCn "$WEBVIEW_ZH"
    json_insert_bool "$report_tmp" localeOverrideSupported "$LOCALE_OVERRIDE_SUPPORTED"
    json_insert_bool "$report_tmp" nativeIntlSupported "$NATIVE_INTL_SUPPORTED"
    json_insert_bool "$report_tmp" settingsPrepared "$SETTINGS_PREPARED"
    json_insert_bool "$report_tmp" nativeUiEnglishConfirmed "$NATIVE_UI_ENGLISH_CONFIRMED"
    json_insert_bool "$report_tmp" languageGateDetected "$LANGUAGE_GATE_DETECTED"
    json_insert_string "$report_tmp" languageGateStatus "$LANGUAGE_GATE_STATUS"
    json_insert_string "$report_tmp" remoteLanguageGateValue "unknown"
    /usr/bin/plutil -insert languageGateEvidence -json "$GATE_EVIDENCE" "$report_tmp" || return 1
    json_insert_bool "$report_tmp" toolIssueSuspected "$TOOL_ISSUE_SUSPECTED"
    json_insert_string "$report_tmp" problemClassification "$PROBLEM_CLASSIFICATION"
    json_insert_string "$report_tmp" mode "$EFFECTIVE_MODE"
    json_insert_string "$report_tmp" copyPath "$(display_path "$COPY_PATH")"
    json_insert_bool "$report_tmp" copyValid "$COPY_VALID"
    json_insert_bool "$report_tmp" copyActivated "$COPY_ACTIVATED"
    json_insert_string "$report_tmp" copySignatureKind "$COPY_SIGNATURE_KIND"
    json_insert_bool "$report_tmp" copyNotarizationAccepted "$COPY_NOTARIZATION_ACCEPTED"
    json_insert_bool "$report_tmp" copyQuarantined "$COPY_QUARANTINED"
    json_insert_string "$report_tmp" copyError "$COPY_ERROR"
    json_insert_bool "$report_tmp" installationReady "$INSTALLATION_READY"
    json_insert_bool "$report_tmp" launchAttempted "$LAUNCH_ATTEMPTED"
    json_insert_bool "$report_tmp" programRunning "$PROGRAM_RUNNING"
    json_insert_bool "$report_tmp" uiLanguageVerified "$UI_LANGUAGE_VERIFIED"
    json_insert_string "$report_tmp" uiVerificationStatus "$UI_VERIFICATION_STATUS"
    json_insert_string "$report_tmp" configPath "$(display_path "$CONFIG_PATH")"
    json_insert_string "$report_tmp" locale "$CURRENT_LOCALE"
    json_insert_bool "$report_tmp" stateValid "$STATE_VALID"
    json_insert_bool "$report_tmp" officialAppUpdated "$SOURCE_CHANGED"
    json_insert_string "$report_tmp" nextAction "$NEXT_ACTION"
    json_insert_string "$report_tmp" logPath "$(display_path "$LOG_FILE")"
    /usr/bin/plutil -convert json "$report_tmp" || return 1
    chmod 600 "$report_tmp" 2>/dev/null || true
    /bin/mv -f -- "$report_tmp" "$REPORT_FILE"
}

show_summary() {
    calculate_next_action
    printf '\nCodex macOS 中文状态\n'
    printf '  官方程序：%s\n' "${APP_PATH:-未找到}"
    printf '  版本：%s（构建 %s）\n' "${APP_VERSION:-未知}" "${BUILD_VERSION:-未知}"
    printf '  机器 / 程序架构：%s / %s\n' "$MACHINE_ARCH" "${APP_ARCHITECTURES:-未知}"
    printf '  官方签名与公证：%s / %s\n' "$SIGNATURE_VALID" "$NOTARIZATION_ACCEPTED"
    printf '  中文资源齐备：%s\n' "$RESOURCES_READY"
    printf '  语言设置准备完成：%s\n' "$SETTINGS_PREPARED"
    printf '  主界面翻译开关：%s（账号实际开关值未知）\n' "$LANGUAGE_GATE_STATUS"
    printf '  安装准备完成：%s\n' "$INSTALLATION_READY"
    printf '  安装模式：%s；独立副本：%s\n' "$EFFECTIVE_MODE" "${COPY_PATH:-未使用}"
    printf '  副本签名：%s（不是官方签名/公证）；副本已启动激活：%s\n' "$COPY_SIGNATURE_KIND" "$COPY_ACTIVATED"
    printf '  程序正在运行：%s（不等于界面已中文）\n' "$PROGRAM_RUNNING"
    printf '  界面中文已确认：%s（需学员人工查看）\n' "$UI_LANGUAGE_VERIFIED"
    if [ "$SETTINGS_PREPARED" = true ] && [ "$INSTALLATION_READY" != true ]; then
        printf '  注意：仅写入中文设置，尚不能确认主界面会加载中文；请勿报告汉化成功。\n'
    fi
    printf '  下一步：%s\n' "$NEXT_ACTION"
    printf '  问题报告：%s\n' "$REPORT_FILE"
}

require_safe_app() {
    if [ -z "$APP_PATH" ]; then STAGE="discover-app"; FAILURE_MESSAGE="没有找到包标识为 $BUNDLE_ID 的官方 Codex。请先安装并打开一次 Codex。"; return 1; fi
    if [ "$SIGNATURE_VALID" != true ] || [ "$NOTARIZATION_ACCEPTED" != true ]; then STAGE="verify-signature"; FAILURE_MESSAGE="官方应用签名或 Apple 公证检查未通过，工具已停止且不会关闭系统安全保护。"; return 1; fi
    if [ "$ARCHITECTURE_COMPATIBLE" != true ]; then STAGE="verify-architecture"; FAILURE_MESSAGE="Codex 程序架构与当前 Mac 不匹配。"; return 1; fi
    if [ "$RESOURCES_READY" != true ]; then STAGE="check-resources"; FAILURE_MESSAGE="官方中文资源或完整性校验未通过。${RESOURCE_CHECK_ERROR}"; return 1; fi
    return 0
}

action_install() {
    info "[1/4] 正在查找并检查官方 Codex.app……"
    inspect_all || true
    require_safe_app || return 1
    ok "官方应用签名、公证、架构和中文资源检查通过"
    # Static gate detection cannot prove this account needs a modified copy.
    if [ "$INSTALL_MODE" = copy ] || { [ "$INSTALL_MODE" = auto ] &&
        { [ "$NATIVE_UI_ENGLISH_CONFIRMED" = true ] || { [ "$EFFECTIVE_MODE" = copy ] && [ "$STATE_VALID" = true ]; }; }; }; then
        EFFECTIVE_MODE=copy
        if [ "$COPY_VALID" != true ] || [ "$STATE_VALID" != true ]; then
            STATE_VALID=false
            info "正在准备独立中文兼容副本（保留官方程序）……"
            prepare_copy || return 1
        else
            ok "已验证现有中文副本，重复安装不再复制"
        fi
    else
        EFFECTIVE_MODE=native; COPY_PATH=""; COPY_VALID=false
    fi
    info "[2/4] 正在备份并写入官方中文语言设置……"
    NATIVE_UI_ENGLISH_CONFIRMED=false
    write_locale_transaction "zh-CN" || return 1
    CURRENT_LOCALE="$(get_locale)"
    info "[3/4] 正在保存已验证状态……"
    install_state_mode=zh-CN
    [ "$EFFECTIVE_MODE" != copy ] || install_state_mode=copy
    write_active_state "$install_state_mode" || {
        if rollback_transaction; then
            FAILURE_MESSAGE="无法保存安装状态，语言配置已回滚，备份仍保留"
        else
            FAILURE_MESSAGE="无法保存安装状态，自动回滚也失败；请把问题报告交给助教，备份仍保留"
        fi
        return 1
    }
    inspect_all || true
    if [ "$SETTINGS_PREPARED" != true ]; then
        if rollback_transaction; then
            FAILURE_MESSAGE="安装后复查未通过，语言配置和启动状态已回滚"
        else
            FAILURE_MESSAGE="安装后复查未通过，自动回滚也失败；请把问题报告交给助教"
        fi
        return 1
    fi
    commit_transaction
    ok "中文资源校验通过，官方语言设置已准备完成"
    if [ "$INSTALLATION_READY" != true ]; then
        warn "主界面翻译生效条件尚未确认。语言设置已写入，但汉化尚未完成；请亲眼检查菜单和主界面。"
    fi
    if [ "$NO_RESTART" -eq 1 ]; then
        info "[4/4] 已按安全默认跳过重启，当前任务不会被关闭。"
        info '请保存当前任务并手动退出 Codex，再双击“macOS-打开中文版.command”。'
    else
        info "[4/4] 正在按要求重新启动 Codex……"
        if [ "$EFFECTIVE_MODE" = copy ]; then
            quit_copy || return 1
            open_copy || return 1
        else
            quit_app || return 1
            open_app || return 1
        fi
        ok "已检测到 Codex 进程；界面中文仍需人工查看确认"
    fi
    classify_language_result
    return 0
}

action_status() {
    STAGE="status"
    inspect_all || true
    if [ "$UI_RESULT" = chinese ]; then
        if [ "$SETTINGS_PREPARED" != true ]; then
            FAILURE_MESSAGE="当前版本资源、签名或中文配置未通过检查，不能登记本次中文验收。"
            return 1
        fi
        UI_LANGUAGE_VERIFIED=true
        UI_VERIFICATION_STATUS="user-confirmed-chinese-this-check"
        INSTALLATION_READY=true
        if [ "$EFFECTIVE_MODE" = native ]; then
            NATIVE_UI_ENGLISH_CONFIRMED=false
            write_active_state zh-CN || return 1
        fi
    elif [ "$UI_RESULT" = english ]; then
        UI_VERIFICATION_STATUS="user-confirmed-english-this-check"
        INSTALLATION_READY=false
        if [ "$EFFECTIVE_MODE" = native ] && [ "$SETTINGS_PREPARED" = true ]; then
            NATIVE_UI_ENGLISH_CONFIRMED=true
            write_active_state zh-CN || return 1
        fi
    fi
    classify_language_result
    return 0
}

action_open() {
    info "正在重新校验官方程序、中文资源和安装状态……"
    inspect_all || true
    require_safe_app || return 1
    STAGE="validate-install-state"
    if [ "$CURRENT_LOCALE" != "zh-CN" ] || [ "$STATE_VALID" != true ] || [ "$SOURCE_CHANGED" = true ]; then
        FAILURE_MESSAGE="中文安装状态无效或官方程序已更新，请先重新运行 macOS 一键安装。"
        return 1
    fi
    if [ "$EFFECTIVE_MODE" = copy ]; then
        open_copy || return 1
    else
        open_app || return 1
    fi
    ok "已检测到 Codex 进程；请人工确认菜单和主界面是否为中文"
    classify_language_result
    return 0
}

action_restore() {
    info "正在备份当前配置并恢复英文……"
    inspect_all || true
    restore_from_copy=false
    [ "$EFFECTIVE_MODE" != copy ] || restore_from_copy=true
    if [ "$NO_RESTART" -ne 1 ] && [ "$restore_from_copy" = true ]; then
        # Stop the managed copy before switching mode; never stop by process name.
        quit_copy || return 1
    fi
    write_locale_transaction "en-US" || return 1
    CURRENT_LOCALE="$(get_locale)"
    EFFECTIVE_MODE=native; COPY_ACTIVATED=false
    NATIVE_UI_ENGLISH_CONFIRMED=false
    if [ -n "$APP_PATH" ]; then
        write_active_state "english" || {
            if rollback_transaction; then
                FAILURE_MESSAGE="无法保存恢复状态，英文配置已回滚，备份仍保留"
            else
                FAILURE_MESSAGE="无法保存恢复状态，自动回滚也失败；请把问题报告交给助教，备份仍保留"
            fi
            return 1
        }
    fi
    commit_transaction
    INSTALLATION_READY=false
    SETTINGS_PREPARED=false
    STATE_VALID=false
    if [ "$NO_RESTART" -eq 1 ]; then
        info "已跳过自动重启；当前任务保持运行，下次启动 Codex 时显示英文。"
    else
        quit_app || return 1
        open_app || return 1
        ok "已检测到 Codex 进程；请人工确认界面已恢复英文"
    fi
    ok "已恢复英文设置；备份、官方程序、对话和其他配置均保留"
    LAST_RESULT="success"
    return 0
}

classify_language_result() {
    LAST_RESULT="success"
    if [ "$UI_RESULT" = english ]; then
        STAGE="ui-language-verification"
        LAST_RESULT="failed"
        FAILURE_MESSAGE="用户确认菜单或主界面仍为英文；汉化未完成，不能仅因配置写入成功而归因上游。"
        if [ "$SETTINGS_PREPARED" = true ]; then
            TOOL_ISSUE_SUSPECTED=true
            PROBLEM_CLASSIFICATION="tool-compatibility-gap"
        else
            PROBLEM_CLASSIFICATION="installation-or-environment-needs-check"
        fi
    elif [ "$SETTINGS_PREPARED" = true ] && [ "$UI_LANGUAGE_VERIFIED" != true ]; then
        LAST_RESULT="partial"
        STAGE="ui-language-verification"
        FAILURE_MESSAGE="安装已准备；请打开中文版并亲眼确认菜单和主界面，尚未完成界面验收。"
        if [ "$EFFECTIVE_MODE" = copy ] && [ "$COPY_VALID" = true ]; then
            PROBLEM_CLASSIFICATION="visual-verification-required"
        elif [ "$LANGUAGE_GATE_DETECTED" = true ] || [ "$LANGUAGE_GATE_STATUS" = unrecognized ]; then
            TOOL_ISSUE_SUSPECTED=true
            PROBLEM_CLASSIFICATION="language-gate-not-covered-by-tool"
        else
            PROBLEM_CLASSIFICATION="runtime-language-verification-required"
        fi
    fi
}

handle_signal() {
    signal_name="$1"
    trap - HUP INT TERM
    if [ "$STAGE" = launch-copy ]; then
        block_failed_copy || warn "无法标记中断副本，请勿继续启动它并把报告交给助教"
    fi
    STAGE="interrupted"
    FAILURE_MESSAGE="操作收到 $signal_name 信号并中断"
    LAST_RESULT="failed"
    if rollback_transaction; then
        FAILURE_MESSAGE="${FAILURE_MESSAGE}；任何未完成的语言配置和启动状态均已回滚"
    else
        FAILURE_MESSAGE="${FAILURE_MESSAGE}；自动回滚失败，请把问题报告和备份交给助教"
    fi
    warn "$FAILURE_MESSAGE"
    if [ "$REPORTING_READY" = true ]; then
        write_report "$LAST_RESULT" "$FAILURE_MESSAGE" || warn "无法保存中断问题报告"
        [ -n "$REPORT_FILE" ] && printf '问题报告：%s\n' "$REPORT_FILE" >&2
    fi
    exit 130
}

main() {
    trap cleanup EXIT
    trap 'handle_signal HUP' HUP
    trap 'handle_signal INT' INT
    trap 'handle_signal TERM' TERM
    parse_args "$@"
    result=0
    if init_paths; then
        info "Codex macOS 中文支持工具 v$TOOL_VERSION"
        case "$ACTION" in
            install) action_install || result=$? ;;
            status) action_status || result=$? ;;
            open) action_open || result=$? ;;
            restore) action_restore || result=$? ;;
        esac
    else
        result=1
    fi
    if [ "$result" -ne 0 ]; then
        LAST_RESULT="failed"
        if [ "$STAGE" = launch-copy ]; then block_failed_copy || warn "无法标记失败副本，请将报告交给助教，勿继续启动这个副本"; fi
        [ -n "$FAILURE_MESSAGE" ] || FAILURE_MESSAGE="操作在 $STAGE 阶段失败"
        warn "$FAILURE_MESSAGE"
    fi
    if [ -n "$APP_PATH" ]; then
        CURRENT_LOCALE="$(get_locale)"
        if [ "$EFFECTIVE_MODE" = copy ]; then
            if copy_running; then PROGRAM_RUNNING=true; fi
        elif is_program_running; then PROGRAM_RUNNING=true; fi
    fi
    if [ "$REPORTING_READY" != true ]; then
        printf '无法创建任何问题报告，请把上面的错误原文交给助教。\n' >&2
        return "$result"
    fi
    if ! write_report "$LAST_RESULT" "$FAILURE_MESSAGE"; then
        warn "无法保存 JSON 问题报告，请把上面的错误交给助教。"
        return 1
    fi
    if [ "$ACTION" = "status" ] && [ "$JSON_OUTPUT" -eq 1 ]; then
        cat "$REPORT_FILE"
    else
        show_summary
    fi
    return "$result"
}

main "$@"
