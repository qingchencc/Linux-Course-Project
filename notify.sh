#!/bin/bash
# ── 服药通知逻辑 ───────────────────────────────────────────
# 接收药品名作为参数，发送系统通知
# 用法: bash notify.sh <药品名>

MED_NAME="${1:-未知药品}"
echo "提醒：现在是服药时间，请服用：${MED_NAME}"

# 桌面通知 (Linux)
if command -v notify-send &>/dev/null; then
    notify-send "💊 服药提醒" "请按时服用: ${MED_NAME}" --urgency=critical 2>/dev/null
fi

# wall 广播作为兜底方案
if command -v wall &>/dev/null; then
    echo "💊 服药提醒: 请按时服用 ${MED_NAME}" | wall 2>/dev/null
fi
