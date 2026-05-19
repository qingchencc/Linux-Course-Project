#!/bin/bash
TARGET_SCRIPT="/home/2350801303/Linux-Course-Project/remind.sh"
LOG_DIR="/home/2350801303/Linux-Course-Project/log"
LOG_FILE="$LOG_DIR/guardian.log"

# 创建日志目录
mkdir -p $LOG_DIR

# 1. 进程监控与自动重启
check_service() {
    if ! pgrep -f "$TARGET_SCRIPT" > /dev/null; then
        echo "[$(date)] 服务崩溃，正在自动重启..." >> $LOG_FILE
        nohup bash "$TARGET_SCRIPT" >> "$LOG_DIR/remind.log" 2>&1 &
    fi
}

# 2. 磁盘空间不足时自动清理日志
check_disk() {
    USE=$(df -h /dev/mmcblk0p2 | grep -v Filesystem | awk '{print $5}' | tr -d '%')
    if [ "$USE" -ge 80 ]; then
        echo "[$(date)] 磁盘使用率 $USE%，清理7天前日志" >> $LOG_FILE
        find "$LOG_DIR" -name "*.log" -mtime +7 -delete
    fi
}

# 主循环：每分钟执行一次
while true; do
    check_service
    check_disk
    sleep 60
done
