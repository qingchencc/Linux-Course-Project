#!/bin/bash
LOG_FILE="meds_history.log"
if [ ! -f "$LOG_FILE" ]; then
    echo "日志文件不存在"
    exit 1
fi
awk -F: '{total++; if($4=="已服") taken++} END {printf "服药统计 - 总次数: %d, 已服: %d, 服药率: %.2f%%\n", total, taken, (taken/total)*100}' $LOG_FILE
