#!/bin/bash
# 检查 notify.sh 是否在运行
if ! pgrep -f "notify.sh" > /dev/null; then
    echo "$(date): 提醒服务已停止，正在重启..." >> guardian.log
    nohup ./notify.sh > /dev/null 2>&1 &
else
    echo "服务运行正常。"
fi
