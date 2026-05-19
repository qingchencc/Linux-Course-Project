#!/bin/bash
#解析meds.conf并生成crontab规则
#使用awk处理时间与药品[cite:16,24]
awk -F:'{print $2,$1,"* * * /home/pi/guardian_project/notify.sh",$3}' meds.conf >
crontab my_cron
echo "调度已更新：已根据meds.conf自动配置crontab"
