#!/bin/bash
# ── 计划同步：将 med.conf 转换为 crontab 格式 ──────────────
# med.conf 格式: HH:MM:药品名
# 输出: my_cron (标准 cron 5 字段格式)
#
# 用法: bash sync_schedule.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/med.conf"
NOTIFY_SCRIPT="${SCRIPT_DIR}/notify.sh"
CRON_OUT="${SCRIPT_DIR}/my_cron"

if [ ! -f "$CONF_FILE" ]; then
    echo "错误: 找不到配置文件 $CONF_FILE"
    exit 1
fi

awk -F: -v notify="$NOTIFY_SCRIPT" '{
    hour = $1
    min = $2
    name = $3
    # 标准 cron 格式: 分 时 日 月 周 命令
    printf "%s %s * * * bash %s %s\n", min, hour, notify, name
}' "$CONF_FILE" > "$CRON_OUT"

echo "定时任务已解析并保存到 my_cron"
