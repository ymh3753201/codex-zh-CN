#!/bin/bash
# Explicit fallback only after the official UI was checked and remains English.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
/bin/bash "$SCRIPT_DIR/scripts/install_macos.sh" --mode copy --action install --no-restart
result=$?
if [ -t 0 ]; then
    printf '\n按回车键关闭此窗口……'
    read -r _
fi
exit "$result"
