#!/bin/bash
# ── 智能服药提醒服务 ──────────────────────────────────────────
# 职责: 每5秒轮询 meds.conf，到服药时间触发系统级通知 (notify-send / wall)
# 被 background_daemon.sh 与 guardian.sh 双重守护，异常退出后自动拉起
#
# 测试验证:
#   bash remind.sh &          # 后台启动
#   REMIND_PID=$!
#   sleep 3
#   ps aux | grep -v grep | grep "remind.sh"   # 期望输出含 remind.sh
#   kill $REMIND_PID 2>/dev/null               # 可正常停止
# ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/meds.conf"
PID_FILE="${SCRIPT_DIR}/log/remind.pid"
LOG_FILE="${SCRIPT_DIR}/log/remind.log"

mkdir -p "${SCRIPT_DIR}/log"

# ── 写入 PID（供外部进程管理）─────────────────────────────────
echo $$ > "$PID_FILE"

# ── 优雅退出（响应 kill / pkill / Ctrl+C）────────────────────
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 提醒服务收到退出信号，正常关闭" >> "$LOG_FILE"
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服药提醒服务启动成功" >> "$LOG_FILE"
echo "服药提醒服务运行中..."

# ── 已通知记录（同一天同一药品同一时间仅弹窗一次）────────────
declare -A NOTIFIED
LAST_CLEANUP=$(date +%Y%m%d)

# ── 主循环：每 5 秒检查一次 ──────────────────────────────────
while true; do
    # 跨天清理已通知记录，避免数组膨胀
    TODAY=$(date +%Y%m%d)
    if [ "$TODAY" != "$LAST_CLEANUP" ]; then
        NOTIFIED=()
        LAST_CLEANUP=$TODAY
    fi

    if [ -f "$CONF_FILE" ]; then
        CURRENT_TIME=$(date +%H:%M)

        while IFS= read -r line || [ -n "$line" ]; do
            # 跳过空行和注释行
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            # 解析 "药品名 HH:MM" 格式（药品名可能含空格）
            MED_TIME=$(echo "$line" | grep -oE '[0-9]{2}:[0-9]{2}$')
            MED_NAME=$(echo "$line" | sed -E 's/[[:space:]]+[0-9]{2}:[0-9]{2}[[:space:]]*$//' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')

            if [ -z "$MED_NAME" ] || [ -z "$MED_TIME" ]; then
                continue
            fi

            # 当前时间匹配服药时间 → 触发通知
            if [ "$CURRENT_TIME" = "$MED_TIME" ]; then
                KEY="${MED_NAME}|${MED_TIME}"

                if [ -z "${NOTIFIED[$KEY]}" ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服药时间到: ${MED_NAME}" >> "$LOG_FILE"

                    # 系统级桌面通知 (Linux)
                    if command -v notify-send &>/dev/null; then
                        notify-send "💊 服药提醒" "请按时服用: ${MED_NAME}" --urgency=critical 2>/dev/null
                    fi

                    # wall 广播作为兜底
                    if command -v wall &>/dev/null; then
                        echo "💊 服药提醒: 请按时服用 ${MED_NAME}" | wall 2>/dev/null
                    fi

                    # 调用 notify.sh（如果存在且未损坏）
                    if [ -x "${SCRIPT_DIR}/notify.sh" ]; then
                        bash "${SCRIPT_DIR}/notify.sh" "$MED_NAME" 2>/dev/null
                    fi

                    NOTIFIED[$KEY]=1
                fi
            fi
        done < "$CONF_FILE"
    fi

    sleep 5
done
