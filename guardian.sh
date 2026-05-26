#!/bin/bash
TARGET_SCRIPT="/home/2350801303/Linux-Course-Project/remind.sh"
LOG_DIR="/home/2350801303/Linux-Course-Project/log"
LOG_FILE="$LOG_DIR/guardian.log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 1. 进程监控与自动重启
check_service() {
    # 更加健壮的进程检查：查找包含目标脚本名的进程，同时排除掉 grep 自身和当前守护脚本
    if ! ps aux | grep "$TARGET_SCRIPT" | grep -v "grep" | grep -v "guardian.sh" > /dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服务崩溃，正在自动重启..." >> "$LOG_FILE"
        # 核心修正：末尾必须加 & 让其在后台运行，否则守护进程会被卡死
        nohup bash "$TARGET_SCRIPT" >> "$LOG_DIR/remind.log" 2>&1 &
    fi
}

# 2. 磁盘空间不足时自动清理日志
check_disk() {
    # 优化：检查根目录 '/'，大幅提升在 Docker 容器与物理机之间的兼容性
    USE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [ "$USE" -ge 80 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 磁盘使用率 $USE%, 触发7天前日志清理" >> "$LOG_FILE"
        # 寻找日志目录下 7 天前的旧日志并删除
        find "$LOG_DIR" -name "*.log" -mtime +7 -delete
        
        # 深度自愈预防：如果清理后空间依然大于90%，说明当前日志写得太快，直接清空当前的 remind.log
        NEW_USE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
        if [ "$NEW_USE" -ge 90 ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 空间仍极度紧张，清空当前活动日志防止爆盘" >> "$LOG_FILE"
            cat /dev/null > "$LOG_DIR/remind.log"
        fi
    fi
}

# 主循环：每分钟执行一次
while true; do
    check_service
    check_disk
    sleep 60
done
