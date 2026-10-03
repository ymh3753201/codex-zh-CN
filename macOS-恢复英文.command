#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
/bin/bash "$SCRIPT_DIR/scripts/install_macos.sh" --action restore --no-restart
result=$?
if [ -t 0 ]; then
    printf '\n按回车键关闭此窗口……'
    read -r _
fi
exit "$result"
