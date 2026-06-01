#!/bin/bash

# --- 路径定义：动态检测项目根目录 ---
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$PROJECT_DIR/meds.conf"
LOG_FILE="$PROJECT_DIR/log/background.log"
REMIND_SCRIPT="$PROJECT_DIR/remind.sh"

# 确保日志目录存在
mkdir -p "$PROJECT_DIR/log"

LAST_MD5=""
echo "[$(date)] 成员B数据解析守护进程启动成功..." >> "$LOG_FILE"

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
    while read -r name time || [ -n "$name" ]; do
        # 略过空行或注释行
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        
        # 验证时间格式是否为 HH:MM
        if [[ $time =~ ^([0-9]{1,2}):([0-9]{2})$ ]]; then
            FORMATTED_TIME="TIME=$time"
            echo "解析成功 -> 药品: [$name] 触发时间设定: [$FORMATTED_TIME]" >> "$LOG_FILE"
        else
            echo "解析失败 -> 药品 [$name] 的时间格式 [$time] 不合法，跳过。" >> "$LOG_FILE"
        fi
    done < "$CONF_FILE"
}

# =====================================================================
# 修正后的原任务 A：基础自愈与磁盘监控
# =====================================================================
check_self_healing_and_disk() {
    # 1. 服务自愈
    if ! ps aux | grep -v grep | grep -q "$REMIND_SCRIPT"; then
        echo "[$(date)] 警告：提醒服务异常！正在尝试盲区自愈..." >> "$LOG_FILE"
        nohup bash "$REMIND_SCRIPT" >> /dev/null 2>&1 &
    fi

    # 2. 磁盘监控
    USE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$USE" -ge 80 ]; then
        find "$PROJECT_DIR/log" -name "*.log" -mtime +7 -delete
    fi
}

# =====================================================================
# 主循环（5秒高频检测，实现秒级感知变动）
# =====================================================================
while true; do
    if [ -f "$CONF_FILE" ]; then
        CURRENT_MD5=$(md5sum "$CONF_FILE" | awk '{print $1}')
        if [ "$CURRENT_MD5" != "$LAST_MD5" ]; then
            parse_config
            LAST_MD5=$CURRENT_MD5
        fi
    fi

    check_self_healing_and_disk
    sleep 5
done
