#!/bin/bash
# ── 服药统计报告 ───────────────────────────────────────────
# 解析服药日志，统计总次数、已服次数和服药率
# 用法: LOG_FILE=log/med_history.log bash audit_report.sh
#
# 日志格式: [YYYY-MM-DD HH:MM] 药品名 - 已服/未服

LOG_FILE="${LOG_FILE:-log/med_history.log}"

if [ ! -f "$LOG_FILE" ]; then
    echo "日志文件不存在: $LOG_FILE"
    exit 1
fi

awk '{
    total++
    if ($0 ~ /已服/) taken++
}
END {
    if (total > 0) {
        rate = (taken / total) * 100
        printf "服药统计 - 总次数: %d, 已服: %d, 服药率: %.2f%%\n", total, taken, rate
    } else {
        print "服药统计 - 暂无记录"
    }
}' "$LOG_FILE"
