#!/bin/bash
# ── 后台数据解析守护进程 ─────────────────────────────────────
# 职责:
#   B. 监控 meds.conf 变更并解析（Hot Reload, 每5秒）
#   A. 基础自愈：检测 remind.sh 异常时自动拉起
#   A. 磁盘监控：使用率 >= 80% 时清理 7 天前的旧日志
#
# 被 guardian.sh 守护

# --- 路径定义：动态检测项目根目录 ---------------------------
# 使用 BASH_SOURCE 替代 $0，在 nohup / source / symlink 场景下更可靠
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
CONF_FILE="$PROJECT_DIR/meds.conf"
LOG_FILE="$PROJECT_DIR/log/background.log"
REMIND_SCRIPT="$PROJECT_DIR/remind.sh"
REMIND_PID_FILE="$PROJECT_DIR/log/remind.pid"

# 确保日志目录存在
mkdir -p "$PROJECT_DIR/log"

# --- 启动信息（帮助定位"找不到文件"类问题）-------------------
echo "[$(date)] ========================================" >> "$LOG_FILE"
echo "[$(date)] 成员B数据解析守护进程启动" >> "$LOG_FILE"
echo "[$(date)] 项目目录: $PROJECT_DIR" >> "$LOG_FILE"
echo "[$(date)] 配置文件: $CONF_FILE" >> "$LOG_FILE"
echo "[$(date)] 日志目录: $PROJECT_DIR/log" >> "$LOG_FILE"
if [ -f "$CONF_FILE" ]; then
    echo "[$(date)] 配置文件状态: 已存在" >> "$LOG_FILE"
else
    echo "[$(date)] 配置文件状态: 不存在，等待创建..." >> "$LOG_FILE"
fi

# --- 跨平台文件校验（md5sum / md5 / cksum 回退）-------------
get_checksum() {
    local file="$1"
    if command -v md5sum &>/dev/null; then
        md5sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v md5 &>/dev/null; then
        md5 "$file" 2>/dev/null | awk '{print $NF}'
    elif command -v cksum &>/dev/null; then
        cksum "$file" 2>/dev/null | awk '{print $1}'
    else
        # 最后回退：用文件大小 + 修改时间拼一个指纹
        stat -c '%s-%Y' "$file" 2>/dev/null || echo "fallback"
    fi
}

LAST_CHECKSUM=""

# =====================================================================
# 核心任务 B：数据解析与分析（Hot Reload 机制）
# =====================================================================
parse_config() {
    echo "[$(date)] 检测到 meds.conf 发生变更，开始解析数据..." >> "$LOG_FILE"

    if [ ! -f "$CONF_FILE" ]; then
        echo "错误：找不到配置文件 $CONF_FILE" >> "$LOG_FILE"
        return
    fi

    # 读取并分析数据，严格对齐为 TIME=HH:MM 格式输出
    while IFS= read -r line || [ -n "$line" ]; do
        # 提取药品名和时间（格式: "药品名 HH:MM"）
        name=$(echo "$line" | sed -E 's/[[:space:]]+[0-9]{1,2}:[0-9]{2}[[:space:]]*$//' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
        time=$(echo "$line" | grep -oE '[0-9]{1,2}:[0-9]{2}$')

        # 略过空行或注释行
        [[ -z "$name" || "$name" =~ ^# ]] && continue

        # 验证时间格式是否为 HH:MM
        if [[ "$time" =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
            FORMATTED_TIME="TIME=$time"
            echo "解析成功 -> 药品: [$name] 触发时间设定: [$FORMATTED_TIME]" >> "$LOG_FILE"
        else
            echo "解析失败 -> 药品 [$name] 的时间格式 [$time] 不合法，跳过。" >> "$LOG_FILE"
        fi
    done < "$CONF_FILE"
}

# =====================================================================
# 任务 A：基础自愈与磁盘监控
# =====================================================================
check_self_healing_and_disk() {
    # 1. 服务自愈：仅在 remind.sh 确实未运行时拉起（防止重复启动）
    local remind_running=false
    if [ -f "$REMIND_PID_FILE" ] && kill -0 "$(cat "$REMIND_PID_FILE" 2>/dev/null)" 2>/dev/null; then
        remind_running=true
    elif pgrep -f "$REMIND_SCRIPT" > /dev/null 2>&1; then
        remind_running=true
    fi

    if ! $remind_running; then
        echo "[$(date)] 警告：提醒服务异常！正在尝试盲区自愈..." >> "$LOG_FILE"
        nohup bash "$REMIND_SCRIPT" >> "$PROJECT_DIR/log/remind.log" 2>&1 &
    fi

    # 2. 磁盘监控（跨平台 df 输出解析）
    local USE
    if df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | grep -q .; then
        USE=$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    elif df -h / 2>/dev/null | awk 'NR==2 {print $5}' | grep -q .; then
        USE=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    else
        USE=0
    fi

    if [ -n "$USE" ] && [ "$USE" -ge 80 ] 2>/dev/null; then
        echo "[$(date)] 磁盘使用率 ${USE}%，清理 7 天前的旧日志..." >> "$LOG_FILE"
        find "$PROJECT_DIR/log" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    fi
}

# --- 优雅退出 --------------------------------------------------
cleanup() {
    echo "[$(date)] 守护进程收到退出信号，正常关闭" >> "$LOG_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

# =====================================================================
# 主循环（5秒高频检测，实现秒级感知变动）
# =====================================================================
while true; do
    if [ -f "$CONF_FILE" ]; then
        CURRENT_CHECKSUM=$(get_checksum "$CONF_FILE")
        if [ "$CURRENT_CHECKSUM" != "$LAST_CHECKSUM" ]; then
            parse_config
            LAST_CHECKSUM="$CURRENT_CHECKSUM"
        fi
    fi

    check_self_healing_and_disk
    sleep 5
done
