#!/bin/bash
# ── 压力测试：sync_schedule.sh 连续执行 100 次 ────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SYNC_SCRIPT="${SCRIPT_DIR}/sync_schedule.sh"

if [ ! -f "$SYNC_SCRIPT" ]; then
    echo "错误: 找不到 sync_schedule.sh"
    exit 1
fi

if [ ! -x "$SYNC_SCRIPT" ]; then
    chmod +x "$SYNC_SCRIPT"
fi

echo "开始压力测试 (100 次 sync_schedule.sh)..."
FAIL_COUNT=0

for i in $(seq 1 100); do
    if ! bash "$SYNC_SCRIPT" > /dev/null 2>&1; then
        ((FAIL_COUNT++))
    fi
done

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "测试完成：100 次执行全部成功，系统未出现阻塞。"
else
    echo "测试完成：100 次执行中 ${FAIL_COUNT} 次失败。"
    exit 1
fi
