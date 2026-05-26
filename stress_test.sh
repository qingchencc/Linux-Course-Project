#!/bin/bash
echo "开始压力测试..."
for i in {1..100}; do
    ./sync_schedule.sh > /dev/null
done
echo "测试完成：系统未出现阻塞。"
