#!/bin/bash
# -----------------------------------------------------------------------------
# notify.sh
# 通知脚本：当 PR 就绪时发送通知到配置的渠道 (Telegram/Discord/Slack)
# -----------------------------------------------------------------------------

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

# 参数
NOTIFICATION_TYPE="$1"  # pr_ready | ci_failed | merged | crashed
TASK_ID="$2"
PR_NUMBER="${3:-}"
PR_URL="${4:-}"
MESSAGE="${5:-}"

CLAWDBOT_DIR="${CLAWDBOT_ROOT:-$HOME/clawdbot}"

# 构建消息
build_message() {
    local type="$1"
    local task_id="$2"
    local pr_num="$3"
    local pr_url="$4"
    local msg="$5"

    case "$type" in
        pr_ready)
            echo "🎉 **PR Ready for Review**%0A%0ATask: \`$task_id\`%0APR: #$pr_num%0ALink: $pr_url%0A%0A$message"
            ;;
        ci_failed)
            echo "❌ **CI Failed**%0A%0ATask: \`$task_id\`%0APR: #$pr_num%0ALink: $pr_url%0A%0A$message"
            ;;
        merged)
            echo "✅ **PR Merged**%0A%0ATask: \`$task_id\`%0APR: #$pr_num%0A%0A$message"
            ;;
        crashed)
            echo "🚨 **Agent Crashed**%0A%0ATask: \`$task_id\`%0A%0A$message"
            ;;
        *)
            echo "📢 **Notification**%0A%0ATask: \`$task_id\`%0A$message"
            ;;
    esac
}

# 发送到 Telegram
send_telegram() {
    local message="$1"

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "  ⚠️ Telegram 未配置 (需要 TELEGRAM_BOT_TOKEN 和 TELEGRAM_CHAT_ID)"
        return 0
    fi

    local url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    curl -s -X POST "$url" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$message" \
        -d "parse_mode=Markdown" \
        > /dev/null

    echo "  ✅ Telegram 通知已发送"
}

# 发送到 Discord
send_discord() {
    local message="$1"

    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        echo "  ⚠️ Discord 未配置 (需要 DISCORD_WEBHOOK_URL)"
        return 0
    fi

    local json_payload=$(cat <<EOF
{
    "content": "$message"
}
EOF
)

    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        > /dev/null

    echo "  ✅ Discord 通知已发送"
}

# 发送到 Slack
send_slack() {
    local message="$1"

    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        echo "  ⚠️ Slack 未配置 (需要 SLACK_WEBHOOK_URL)"
        return 0
    fi

    # Slack 需要不同的 JSON 格式
    local json_payload=$(cat <<EOF
{
    "text": "$message"
}
EOF
)

    curl -s -X POST "$SLACK_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        > /dev/null

    echo "  ✅ Slack 通知已发送"
}

# 主逻辑
main() {
    if [ -z "$NOTIFICATION_TYPE" ] || [ -z "$TASK_ID" ]; then
        echo "用法: $0 <type> <task_id> [pr_number] [pr_url] [message]"
        echo "类型: pr_ready | ci_failed | merged | crashed"
        exit 1
    fi

    echo "📤 发送通知: $NOTIFICATION_TYPE for $TASK_ID"

    # 构建消息
    MESSAGE=$(build_message "$NOTIFICATION_TYPE" "$TASK_ID" "$PR_NUMBER" "$PR_URL" "$MESSAGE")

    # 发送到所有配置的渠道
    send_telegram "$MESSAGE"
    send_discord "$MESSAGE"
    send_slack "$MESSAGE"

    echo "✅ 通知完成"
}

main
