#!/bin/bash
# 自动定位项目根目录，Web 集成友好型脚本
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SCRIPT_DIR/log"
LOG_FILE="$LOG_DIR/guardian.log"
CONF_FILE="$SCRIPT_DIR/meds.conf"
TARGET_SCRIPT="$SCRIPT_DIR/remind.sh"

mkdir -p "$LOG_DIR"

# 1. 进程自愈逻辑
check_service() {
    # 查找进程时使用绝对路径避免歧义
    if ! ps aux | grep -v "grep" | grep -F "$TARGET_SCRIPT" > /dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 发现服务异常，正在重启..." >> "$LOG_FILE"
        nohup bash "$TARGET_SCRIPT" >> "$LOG_DIR/remind.log" 2>&1 &
    fi
}

# 2. 磁盘管理逻辑
check_disk() {
    # 增加对分区空间的健壮性检查
    USE=$(df -h "$SCRIPT_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$USE" -ge 80 ]; then
        find "$LOG_DIR" -name "*.log" -mtime +7 -delete
    fi
}

# 3. 循环监控主逻辑
while true; do
    check_service
    check_disk
    sleep 60
done
