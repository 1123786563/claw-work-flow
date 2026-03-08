#!/bin/bash
# -----------------------------------------------------------------------------
# setup-cron.sh
# 配置定时任务：监控循环 (每10分钟) + 每日清理 (凌晨3点)
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWDBOT_ROOT="${CLAWDBOT_ROOT:-$HOME/clawdbot}"

echo "⏰ 配置 ClawdBot 定时任务..."

# 检查 crontab 是否安装
if ! command -v crontab &> /dev/null; then
    echo "❌ crontab 未安装，请先安装"
    exit 1
fi

# 创建临时文件
TEMP_CRON=$(mktemp)

# 导出现有 crontab（如果存在）
crontab -l > "$TEMP_CRON" 2>/dev/null || true

# 移除旧的 clawdbot 任务（避免重复）
sed -i '' '/clawdbot/d' "$TEMP_CRON" 2>/dev/null || sed -i '/clawdbot/d' "$TEMP_CRON" 2>/dev/null || true

# 添加新任务
cat >> "$TEMP_CRON" << EOF

# ClawdBot 自动化任务
*/10 * * * * $CLAWDBOT_ROOT/scripts/check-agents.sh >> $CLAWDBOT_ROOT/logs/cron-monitor.log 2>&1
0 3 * * * $CLAWDBOT_ROOT/scripts/cleanup.sh >> $CLAWDBOT_ROOT/logs/cron-cleanup.log 2>&1
EOF

# 安装新 crontab
crontab "$TEMP_CRON"
rm "$TEMP_CRON"

echo ""
echo "✅ 定时任务已配置:"
echo ""
echo "   📊 监控循环: 每 10 分钟"
echo "   🧹 每日清理: 凌晨 3:00"
echo ""
echo "📝 查看已配置任务:"
echo "   crontab -l | grep clawdbot"
echo ""
echo "📂 日志位置:"
echo "   $CLAWDBOT_ROOT/logs/cron-monitor.log"
echo "   $CLAWDBOT_ROOT/logs/cron-cleanup.log"
