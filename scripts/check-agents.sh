#!/bin/bash
# -----------------------------------------------------------------------------
# check-agents.sh
# 监控与自愈脚本：检查 Agent 活跃状态、PR 及 CI 状态，并更新 JSON。
# -----------------------------------------------------------------------------

set -e

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

CLAWDBOT_DIR="${CLAWDBOT_ROOT:-$HOME/clawdbot}"
REGISTRY_FILE="${ACTIVE_TASKS_FILE:-$CLAWDBOT_DIR/active-tasks.json}"

if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo "未找到注册文件: $REGISTRY_FILE"
    exit 0
fi

echo "正在运行 Monitor Loop..."

# 使用 python 脚本执行核心逻辑
python3 "$CLAWDBOT_DIR/scripts/check_agents.py"
