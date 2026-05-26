#!/bin/bash
# 使用单引号防止变量被提前解析
awk -F: '{print $2, $1, "* * * /home/pi/guardian_project/notify.sh", $3}' med.conf > my_cron
echo "定时任务已解析并保存到 my_cron"
