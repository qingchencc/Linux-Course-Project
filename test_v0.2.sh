#!/bin/bash
# 成员 C - v0.2 异常模拟与工程质量测试脚本

echo "=== 开始 v0.2 阶段异常性测试 ==="

# 任务 A：模拟配置文件权限错误 (验证成员 B 的脚本鲁棒性)
echo "[测试 1] 模拟 meds.conf 权限不足..."
touch meds.conf
chmod 000 meds.conf
# 此时如果运行解析脚本，应能看到错误处理逻辑
ls -l meds.conf

# 任务 B：模拟关键服务脚本丢失 (验证成员 A 的自愈能力)
echo "[测试 2] 模拟 guardian.sh 守护脚本意外丢失..."
if [ -f "guardian.sh" ]; then
    mv guardian.sh guardian.sh.bak
    echo "状态：已将 guardian.sh 重命名，请检查系统是否能自动恢复或报警。"
else
    echo "状态：未找到 guardian.sh，请确保成员 A 已提交基础脚本。"
fi

# 任务 C：模拟日志文件占用过高 (验证成员 A 的清理功能)
echo "[测试 3] 模拟日志写满磁盘..."
dd if=/dev/zero of=system.log bs=1M count=10
echo "状态：已生成 10MB 测试日志，观察清理脚本是否会自动执行 find/df 操作。"

echo "=== 测试指令发放完毕 ==="
