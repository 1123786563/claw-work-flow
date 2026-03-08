#!/bin/bash

# Zoe - 主协调器
# 负责任务分解、prompt 生成、模型选择

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

TASK="$1"
CONTEXT_FILE="$2"
CLAWDBOT_ROOT="${CLAWDBOT_ROOT:-$HOME/clawdbot}"

echo "🧠 Zoe analyzing task: $TASK"

# ... (中间部分保持不变) ...

# 确定默认模型 (从 .env 获取)
if [ "$AGENT" == "claude" ]; then
    MODEL="${CLAUDE_MODEL:-claude-3-5-sonnet-20241022}"
elif [ "$AGENT" == "gemini" ]; then
    MODEL="${GEMINI_MODEL:-gemini-2.0-flash-exp}"
else
    MODEL="${CLAUDE_MODEL:-claude-3-5-sonnet-20241022}" # fallback
fi

# 读取上下文 (会议记录、用户笔记等)
if [ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ]; then
  CONTEXT=$(cat "$CONTEXT_FILE")
else
  CONTEXT="No additional context provided"
fi

# 使用 Claude 分析任务并决定使用哪个 agent
DECISION=$(claude --model claude-3-5-sonnet-20241022 \
  --dangerously-skip-permissions \
  -p "You are Zoe, an AI orchestrator for a software development team.
Your job is to analyze tasks and decide which coding agent should handle them.

Available agents:
- claude: Best for frontend work, git operations, quick fixes
- gemini: Best for UI/UX design, creative solutions, visual work

Task: $TASK

Context:
$CONTEXT

Output JSON format:
{
  \"agent\": \"claude|gemini\",
  \"reason\": \"why this agent\",
  \"prompt\": \"detailed prompt for the agent including all context\",
  \"priority\": \"high|medium|low\"
}

Respond with ONLY the JSON, no other text.")

# 提取并清理 JSON (去除 Markdown 代码块标记)
CLEAN_JSON=$(echo "$DECISION" | sed 's/```json//g; s/```//g' | sed -n '/^{/,/^}/p')
if [ -z "$CLEAN_JSON" ]; then
  # Fallback: 如果没有找到花括号，尝试直接使用原始输出
  CLEAN_JSON="$DECISION"
fi

# 解析决策
AGENT=$(echo "$CLEAN_JSON" | jq -r '.agent' 2>/dev/null || echo "null")
PROMPT=$(echo "$CLEAN_JSON" | jq -r '.prompt' 2>/dev/null || echo "null")
PRIORITY=$(echo "$CLEAN_JSON" | jq -r '.priority' 2>/dev/null || echo "null")

if [ "$AGENT" == "null" ] || [ -z "$AGENT" ]; then
    echo "❌ 无法解析 Agent 决策。原始输出: $DECISION"
    exit 1
fi

echo "📋 Decision:"
echo "   Agent: $AGENT"
echo "   Priority: $PRIORITY"

# 确定默认模型 (从 .env 获取)
if [ "$AGENT" == "claude" ]; then
    MODEL="${CLAUDE_MODEL:-claude-3-5-sonnet-20241022}"
elif [ "$AGENT" == "gemini" ]; then
    MODEL="${GEMINI_MODEL:-gemini-2.0-flash-exp}"
else
    MODEL="${CLAUDE_MODEL:-claude-3-5-sonnet-20241022}" # fallback
fi

# 生成任务 ID 和 Prompt 文件
TASK_ID="task-$(date +%Y%m%d-%H%M%S)"
PROMPT_FILE="/tmp/clawdbot-prompt-${TASK_ID}.txt"
echo "$PROMPT" > "$PROMPT_FILE"

echo "🚀 Spawning agent..."
"$CLAWDBOT_ROOT/scripts/spawn-agent.sh" \
    --task-id "$TASK_ID" \
    --agent "$AGENT" \
    --model "$MODEL" \
    --repo "$(pwd)" \
    --prompt-file "$PROMPT_FILE"

echo "✅ Task $TASK_ID dispatched to $AGENT"
