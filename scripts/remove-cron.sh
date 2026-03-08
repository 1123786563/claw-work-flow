#!/bin/bash
# -----------------------------------------------------------------------------
# remove-cron.sh
# 移除 ClawdBot 相关的定时任务
# -----------------------------------------------------------------------------

echo "🗑️ 移除 ClawdBot 定时任务..."

TEMP_CRON=$(mktemp)

# 导出现有 crontab
if crontab -l > "$TEMP_CRON" 2>/dev/null; then
    # 移除 clawdbot 相关行
    sed -i '' '/clawdbot/d' "$TEMP_CRON" 2>/dev/null || sed -i '/clawdbot/d' "$TEMP_CRON" 2>/dev/null || true

    # 如果文件为空或只有空行，清空 crontab
    if [ -s "$TEMP_CRON" ]; then
        crontab "$TEMP_CRON"
    else
        crontab -r 2>/dev/null || true
    fi

    echo "✅ 定时任务已移除"
else
    echo "ℹ️ 没有找到定时任务"
fi

rm -f "$TEMP_CRON"
