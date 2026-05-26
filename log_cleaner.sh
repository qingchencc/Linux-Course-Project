#!/bin/bash
LOG_FILE="meds_history.log"
# 如果日志文件超过 1MB (1024KB) 则清理
if [ $(du -k "$LOG_FILE" | cut -f1) -gt 1024 ]; then
    echo "警告：日志过大，正在清空..."
    > "$LOG_FILE"
fi
