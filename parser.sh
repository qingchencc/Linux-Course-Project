#!/bin/bash
# 职责：监控 meds.conf 变更，并校验格式
# 1. 配置路径（动态检测项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/meds.conf"

# 2. 存储上一次的变更时间戳
LAST_CHECK=""
RUNNING=true

# 优雅退出
cleanup() { RUNNING=false; echo ""; echo "解析器正常退出"; }
trap cleanup SIGTERM SIGINT SIGHUP

echo "解析器启动，正在监控 $CONF_FILE 的变更..."

while $RUNNING; do
    # 检查文件是否存在
    if [ -f "$CONF_FILE" ]; then
        # 获取文件的最后修改时间戳
        CURRENT_CHECK=$(stat -c %Y "$CONF_FILE")
        
        if [ "$CURRENT_CHECK" != "$LAST_CHECK" ]; then
            echo "--- 检测到配置文件变更，正在执行安检与热加载 ---"
            
            # 校验格式 (符合协议里的规则)
            # 这里检查 TIME 是否符合 HH:MM 格式
            TIME_VAL=$(grep "TIME=" "$CONF_FILE" | cut -d'=' -f2)
            
            if [[ "$TIME_VAL" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
                echo "[SUCCESS] 格式校验通过，已热加载新时间: $TIME_VAL"
            else
                echo "[ERROR] 配置校验失败：TIME 格式必须为 HH:MM"
            fi
            
            LAST_CHECK=$CURRENT_CHECK
        fi
    fi
    # 每 5 秒监控一次，减少 CPU 占用
    sleep 5
done
