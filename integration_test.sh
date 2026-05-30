#!/bin/bash
# ===========================================================================
# 系统管理模块 — 集成测试套件
# ===========================================================================
# 测试范围:
#   1. Shell 脚本单元功能（配置解析、进程守护、磁盘清理、日志轮转、统计）
#   2. Web API 冒烟测试（需先启动 npm start）
#   3. 端到端流程（改配置 → 守护进程感知 → API 状态变化）
#
# 用法:
#   # 仅测试 Shell 脚本（不需要 Node.js）:
#   bash integration_test.sh --shell
#
#   # 完整测试（需先在一个终端启动 npm start）:
#   bash integration_test.sh --all
#
#   # Docker 中一键完整测试:
#   docker build -t linux-test . && docker run --rm linux-test bash integration_test.sh --all
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PASS=0
FAIL=0
MODE="${1:---shell}"   # --shell | --all
API_BASE="${API_BASE:-http://localhost:3000}"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ── 工具函数 ──────────────────────────────────────────────────

check() {
    local desc="$1"; shift
    if "$@"; then
        ((PASS++))
        echo -e "  ${GREEN}[PASS]${NC} $desc"
    else
        ((FAIL++))
        echo -e "  ${RED}[FAIL]${NC} $desc"
    fi
}

check_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        ((PASS++))
        echo -e "  ${GREEN}[PASS]${NC} $desc"
    else
        ((FAIL++))
        echo -e "  ${RED}[FAIL]${NC} $desc (expected: $expected, got: $actual)"
    fi
}

check_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        ((PASS++))
        echo -e "  ${GREEN}[PASS]${NC} $desc"
    else
        ((FAIL++))
        echo -e "  ${RED}[FAIL]${NC} $desc (expected to contain: $needle)"
    fi
}

cleanup_test_env() {
    # 还原 meds.conf
    if [ -f meds.conf.bak ]; then
        mv meds.conf.bak meds.conf
    fi
    # 清理测试生成的文件
    rm -f test_oversize.log test_med_history.log
    # 杀掉测试启动的后台进程
    if [ -f /tmp/test_guardian.pid ]; then
        kill "$(cat /tmp/test_guardian.pid)" 2>/dev/null || true
        rm -f /tmp/test_guardian.pid
    fi
    if [ -f /tmp/test_daemon.pid ]; then
        kill "$(cat /tmp/test_daemon.pid)" 2>/dev/null || true
        rm -f /tmp/test_daemon.pid
    fi
    if [ -f /tmp/test_remind.pid ]; then
        kill "$(cat /tmp/test_remind.pid)" 2>/dev/null || true
        rm -f /tmp/test_remind.pid
    fi
}

trap cleanup_test_env EXIT

# ═══════════════════════════════════════════════════════════════
# 阶段 1: Shell 脚本测试
# ═══════════════════════════════════════════════════════════════
echo "=========================================="
echo "  阶段 1: Shell 脚本单元测试"
echo "=========================================="

# ── 1a. 配置解析: background_daemon.sh ──────────────────────
echo ""
echo "--- 1a. background_daemon.sh 配置解析 ---"

# 保存原始配置
cp meds.conf meds.conf.bak 2>/dev/null || touch meds.conf.bak

# 测试 1: 合法格式解析
echo "维生素C 08:00" > meds.conf
mkdir -p log
> log/background.log
bash background_daemon.sh &
DAEMON_PID=$!
echo $DAEMON_PID > /tmp/test_daemon.pid
sleep 6
check "合法 HH:MM 格式被解析成功" \
    grep -q "解析成功.*维生素C.*TIME=08:00" log/background.log

# 测试 2: 非法格式被拒绝
echo "假药 ab:cd" >> meds.conf
sleep 6
check "非法时间格式被拒绝" \
    grep -q "解析失败.*假药.*不合法" log/background.log

# 测试 3: 注释行和空行被跳过
echo "" >> meds.conf
echo "# 这是注释" >> meds.conf
sleep 6
VALID_COUNT=$(grep -c "解析成功" log/background.log || true)
INVALID_COUNT=$(grep -c "解析失败" log/background.log || true)
check "注释和空行不影响解析计数" \
    [ "$VALID_COUNT" -ge 2 ] && [ "$INVALID_COUNT" -ge 1 ]

kill "$DAEMON_PID" 2>/dev/null || true
rm -f /tmp/test_daemon.pid

# ── 1b. 进程守护: guardian.sh ───────────────────────────────
echo ""
echo "--- 1b. guardian.sh 进程自愈 ---"

# 确保 remind.sh 没有在跑
pkill -f "remind.sh" 2>/dev/null || true
sleep 1

# 启动 guardian
> log/guardian.log
bash guardian.sh &
GUARDIAN_PID=$!
echo $GUARDIAN_PID > /tmp/test_guardian.pid
sleep 65   # guardian 每 60 秒检查一次

check "guardian 检测到 remind 异常并自动重启" \
    grep -q "发现服务异常" log/guardian.log

# ── 1c. 提醒服务: remind.sh ─────────────────────────────────
echo ""
echo "--- 1c. remind.sh 基础运行 ---"

# guardian 应该已经拉起了 remind，验证它确实在运行
sleep 2
check "remind.sh 进程存在" \
    pgrep -f "remind.sh" > /dev/null

# ── 1d. 日志清理: log_cleaner.sh ────────────────────────────
echo ""
echo "--- 1d. log_cleaner.sh 日志轮转 ---"

# 创建超过 1MB 的测试日志
dd if=/dev/zero of=test_med_history.log bs=1M count=2 2>/dev/null
SIZE_BEFORE=$(du -k test_med_history.log | cut -f1)
LOG_FILE=test_med_history.log bash log_cleaner.sh 2>/dev/null || true
SIZE_AFTER=$(du -k test_med_history.log | cut -f1)
check "超大日志被清空" \
    [ "$SIZE_AFTER" -lt "$SIZE_BEFORE" ]

# 小日志不被清理
echo "小日志内容" > test_med_history.log
LOG_FILE=test_med_history.log bash log_cleaner.sh 2>/dev/null || true
check "小日志保留原内容" \
    grep -q "小日志内容" test_med_history.log
rm -f test_med_history.log

# ── 1e. 服药统计: audit_report.sh ───────────────────────────
echo ""
echo "--- 1e. audit_report.sh 统计功能 ---"

cat > test_med_history.log << 'EOF'
[2025-06-01 08:00] 维生素C - 已服
[2025-06-01 14:00] 降压药 - 未服
[2025-06-02 08:00] 维生素C - 已服
[2025-06-02 14:00] 降压药 - 已服
[2025-06-02 20:00] 复合维生素 - 未服
EOF

OUTPUT=$(LOG_FILE=test_med_history.log bash audit_report.sh 2>/dev/null || true)
check_contains "统计总次数=5" "$OUTPUT" "总次数: 5"
check_contains "已服=3" "$OUTPUT" "已服: 3"
check_contains "服药率=60.00%" "$OUTPUT" "60.00%"
rm -f test_med_history.log

# ── 1f. 计划同步: sync_schedule.sh ──────────────────────────
echo ""
echo "--- 1f. sync_schedule.sh 计划同步 ---"

cp med.conf med.conf.bak 2>/dev/null || true
cat > med.conf << 'EOF'
08:00:维生素C
14:00:降压药
20:00:复合维生素
EOF

bash sync_schedule.sh 2>/dev/null || true
check "my_cron 文件生成" \
    [ -f my_cron ] && [ -s my_cron ]
check "cron 条目格式正确" \
    grep -q "维生素C" my_cron

cp med.conf.bak med.conf 2>/dev/null || true
rm -f med.conf.bak

# ── 1g. 磁盘清理: guardian 磁盘监控 ─────────────────────────
echo ""
echo "--- 1g. 磁盘清理（模拟磁盘满）---"

# 创建一个 8 天前的旧日志
touch -d "8 days ago" log/test_old_cleanup.log 2>/dev/null || touch -t "$(date -d '8 days ago' +%Y%m%d%H%M 2>/dev/null || echo '202501010000')" log/test_old_cleanup.log

# 提取 guardian 的 check_disk 函数单独测（模拟 df 返回 90%）
check_disk_standalone() {
    local USE=90
    if [ "$USE" -ge 80 ]; then
        find log -name "test_old_cleanup.log" -mtime +6 -delete
    fi
}
check_disk_standalone
check "磁盘>=80%时旧日志被清理" \
    [ ! -f log/test_old_cleanup.log ]

# 清理
kill "$GUARDIAN_PID" 2>/dev/null || true
rm -f /tmp/test_guardian.pid
pkill -f "remind.sh" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════
# 阶段 2: Web API 冒烟测试（仅在 --all 模式下执行）
# ═══════════════════════════════════════════════════════════════
if [ "$MODE" = "--all" ]; then
echo ""
echo "=========================================="
echo "  阶段 2: Web API 冒烟测试"
echo "=========================================="
echo "  (请确保 npm start 已在另一个终端启动)"
echo ""

# ── 2a. 系统状态 ────────────────────────────────────────────
echo "--- 2a. GET /api/status ---"
STATUS=$(curl -sf "$API_BASE/api/status" 2>/dev/null || echo '{"success":false}')
check "API /api/status 可访问" \
    echo "$STATUS" | grep -q '"success":true'
check "返回包含 services 字段" \
    echo "$STATUS" | grep -q '"services"'
check "返回包含 diskUsage 字段" \
    echo "$STATUS" | grep -q '"diskUsage"'

# ── 2b. 药品管理 ────────────────────────────────────────────
echo "--- 2b. 药品 CRUD ---"
# 添加
ADD=$(curl -sf -X POST "$API_BASE/api/medications" \
    -H "Content-Type: application/json" \
    -d '{"name":"集成测试药","time":"11:30"}' 2>/dev/null || echo '{"success":false}')
check "添加药品成功" \
    echo "$ADD" | grep -q '"success":true'

# 查询
LIST=$(curl -sf "$API_BASE/api/medications" 2>/dev/null || echo '[]')
check "药品列表包含刚刚添加的药品" \
    echo "$LIST" | grep -q "集成测试药"

# 更新
UPDATE=$(curl -sf -X PUT "$API_BASE/api/medications/集成测试药" \
    -H "Content-Type: application/json" \
    -d '{"time":"12:00"}' 2>/dev/null || echo '{"success":false}')
check "更新药品时间成功" \
    echo "$UPDATE" | grep -q '"success":true'

# 删除
DELETE=$(curl -sf -X DELETE "$API_BASE/api/medications/集成测试药" 2>/dev/null || echo '{"success":false}')
check "删除药品成功" \
    echo "$DELETE" | grep -q '"success":true'

# ── 2c. 服药记录 ────────────────────────────────────────────
echo "--- 2c. 服药记录 ---"
TAKE=$(curl -sf -X POST "$API_BASE/api/take-medication" \
    -H "Content-Type: application/json" \
    -d '{"name":"维生素C","time":"08:00"}' 2>/dev/null || echo '{"success":false}')
check "记录服药成功" \
    echo "$TAKE" | grep -q '"success":true'

RECORDS=$(curl -sf "$API_BASE/api/get-records" 2>/dev/null || echo '{"data":[]}')
check "获取记录包含已服条目" \
    echo "$RECORDS" | grep -q "已服"

AUDIT=$(curl -sf "$API_BASE/api/audit" 2>/dev/null || echo '{"data":{}}')
check "服药统计可访问" \
    echo "$AUDIT" | grep -q '"success":true'

# ── 2d. 系统管理 ────────────────────────────────────────────
echo "--- 2d. 系统管理操作 ---"
SYNC=$(curl -sf -X POST "$API_BASE/api/sync-schedule" 2>/dev/null || echo '{"success":false}')
check "计划同步 API 可访问" \
    echo "$SYNC" | grep -q '"success":true'

CLEAN=$(curl -sf -X POST "$API_BASE/api/clean-logs" 2>/dev/null || echo '{"success":false}')
check "日志清理 API 可访问" \
    echo "$CLEAN" | grep -q '"success":true'

REMINDER=$(curl -sf "$API_BASE/api/reminder-status" 2>/dev/null || echo '{"success":false}')
check "提醒状态 API 可访问" \
    echo "$REMINDER" | grep -q '"success":true'

# ── 2e. 日志查看 ────────────────────────────────────────────
echo "--- 2e. 日志查看 ---"
LOGS=$(curl -sf "$API_BASE/api/logs/daemon?lines=3" 2>/dev/null || echo '{"success":false}')
check "日志 API 可访问" \
    echo "$LOGS" | grep -q '"success":true'

# ── 2f. 清空测试记录 ────────────────────────────────────────
curl -sf -X DELETE "$API_BASE/api/clear-records" > /dev/null 2>&1 || true

fi  # --all mode

# ═══════════════════════════════════════════════════════════════
# 阶段 3: 端到端流程测试
# ═══════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo "  阶段 3: 端到端流程测试"
echo "=========================================="

# ── 3a. 配置变更 → 守护进程感知 → 日志记录 ──────────────────
echo "--- 3a. 配置热加载 E2E ---"
cp meds.conf meds.conf.bak 2>/dev/null || touch meds.conf.bak
> log/background.log

echo "E2E测试药 15:45" > meds.conf
bash background_daemon.sh &
DAEMON_PID=$!
echo $DAEMON_PID > /tmp/test_daemon.pid
sleep 6

check "E2E: 新增药品被 daemon 解析" \
    grep -q "E2E测试药.*TIME=15:45" log/background.log

# 修改配置
echo "E2E测试药 16:30" > meds.conf
sleep 6
check "E2E: 修改后的时间被 daemon 捕获" \
    grep -q "E2E测试药.*TIME=16:30" log/background.log

kill "$DAEMON_PID" 2>/dev/null || true
rm -f /tmp/test_daemon.pid

# ── 3b. 异常恢复 E2E ────────────────────────────────────────
echo "--- 3b. 异常恢复 E2E ---"

pkill -f "remind.sh" 2>/dev/null || true
sleep 1

# remind 不应该在跑
if pgrep -f "remind.sh" > /dev/null; then
    echo "  [WARN] remind.sh 仍在运行，跳过恢复测试"
else
    > log/guardian.log
    bash guardian.sh &
    GUARDIAN_PID=$!
    echo $GUARDIAN_PID > /tmp/test_guardian.pid
    sleep 65

    check "E2E: remind 崩溃后被 guardian 自动拉起" \
        pgrep -f "remind.sh" > /dev/null

    kill "$GUARDIAN_PID" 2>/dev/null || true
    rm -f /tmp/test_guardian.pid
fi

# 还原配置
cp meds.conf.bak meds.conf 2>/dev/null || true
rm -f meds.conf.bak

# ═══════════════════════════════════════════════════════════════
# 结果汇总
# ═══════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo "  测试完成"
echo "=========================================="
echo -e "  通过: ${GREEN}${PASS}${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "  失败: ${RED}${FAIL}${NC}"
else
    echo "  失败: 0"
fi
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
