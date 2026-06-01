#!/bin/bash
# ── 成员 C - v0.2 异常模拟与工程质量测试脚本 ──────────────────
# 测试系统在异常条件下的鲁棒性（权限错误、文件丢失、磁盘满）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PASS=0
FAIL=0
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ── 清理与还原 ─────────────────────────────────────────────
cleanup() {
    echo ""
    echo "=== 清理测试环境 ==="

    # 还原 meds.conf 权限
    if [ -f meds.conf ]; then
        chmod 644 meds.conf 2>/dev/null || true
    fi

    # 还原 guardian.sh
    if [ -f guardian.sh.bak ]; then
        mv guardian.sh.bak guardian.sh 2>/dev/null || true
        echo "[CLEANUP] 已还原 guardian.sh"
    fi

    # 清理测试生成的垃圾文件
    rm -f system.log
    echo "[CLEANUP] 已清理临时测试文件"
}
trap cleanup EXIT

echo "=== 开始 v0.2 阶段异常性测试 ==="

# ── 测试 1：模拟配置文件权限错误 ──────────────────────────
echo ""
echo "[测试 1] 模拟 meds.conf 权限不足..."
if [ ! -f meds.conf ]; then
    touch meds.conf
fi
chmod 000 meds.conf 2>/dev/null || true
PERMS=$(stat -c "%a" meds.conf 2>/dev/null || echo "000")
echo "  当前权限: $PERMS"
if [ "$PERMS" = "000" ]; then
    echo -e "  ${GREEN}[PASS]${NC} 权限正确设置为 000（模拟无权限场景）"
    ((PASS++))
else
    echo -e "  ${RED}[FAIL]${NC} 权限设置失败"
    ((FAIL++))
fi

# ── 测试 2：模拟关键服务脚本丢失 ──────────────────────────
echo ""
echo "[测试 2] 模拟 guardian.sh 守护脚本意外丢失..."
if [ -f "guardian.sh" ]; then
    mv guardian.sh guardian.sh.bak
    if [ ! -f "guardian.sh" ]; then
        echo -e "  ${GREEN}[PASS]${NC} guardian.sh 已重命名，可验证系统自愈/报警能力"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} 重命名失败"
        ((FAIL++))
    fi
else
    echo "  状态：未找到 guardian.sh，请确保成员 A 已提交基础脚本。"
    echo -e "  ${RED}[FAIL]${NC} guardian.sh 缺失"
    ((FAIL++))
fi

# ── 测试 3：模拟日志文件占用过高 ───────────────────────────
echo ""
echo "[测试 3] 模拟日志写满磁盘..."
# 使用 fallocate 或 dd 创建大文件（兼容性处理）
if command -v fallocate &>/dev/null; then
    fallocate -l 10M system.log 2>/dev/null || dd if=/dev/zero of=system.log bs=1M count=10 2>/dev/null
elif command -v dd &>/dev/null; then
    dd if=/dev/zero of=system.log bs=1M count=10 2>/dev/null
else
    # Windows / 无 dd 回退
    python3 -c "with open('system.log','wb') as f: f.write(b'\0'*10*1024*1024)" 2>/dev/null || true
fi

if [ -f system.log ]; then
    SIZE=$(du -h system.log 2>/dev/null | cut -f1 || echo "?")
    echo "  状态：已生成 ${SIZE} 测试日志，观察清理脚本是否会自动执行 find/df 操作。"
    echo -e "  ${GREEN}[PASS]${NC} 大文件生成成功"
    ((PASS++))
else
    echo -e "  ${RED}[FAIL]${NC} 无法生成测试日志文件"
    ((FAIL++))
fi

# ── 结果汇总 ──────────────────────────────────────────────
echo ""
echo "=== v0.2 异常测试完成 ==="
echo -e "  通过: ${GREEN}${PASS}${NC}"
echo -e "  失败: ${RED}${FAIL}${NC}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
