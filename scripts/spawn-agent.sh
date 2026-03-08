#!/bin/bash
# -----------------------------------------------------------------------------
# spawn-agent.sh
# 核心调度脚本：为 Agent (Codex/Claude) 创建隔离环境(worktree)，拉起 tmux 进程，并记录状态。
# -----------------------------------------------------------------------------

set -e

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

# 参数解析
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --task-id) TASK_ID="$2"; shift ;;
        --agent) AGENT_TYPE="$2"; shift ;;
        --model) MODEL="$2"; shift ;;
        --repo) REPO_PATH="$2"; shift ;;
        --prompt-file) PROMPT_FILE="$2"; shift ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$TASK_ID" || -z "$AGENT_TYPE" || -z "$MODEL" || -z "$REPO_PATH" || -z "$PROMPT_FILE" ]]; then
    echo "用法: $0 --task-id <id> --agent <codex|claude> --model <model_name> --repo <repo_path> --prompt-file <path>"
    exit 1
fi

CLAWDBOT_DIR="${CLAWDBOT_ROOT:-$HOME/clawdbot}"
WORKTREE_DIR="${WORKTREE_BASE:-$CLAWDBOT_DIR/worktrees}/$TASK_ID"
REGISTRY_FILE="${ACTIVE_TASKS_FILE:-$CLAWDBOT_DIR/active-tasks.json}"
BRANCH_NAME="feat/$TASK_ID"
TMUX_SESSION="$AGENT_TYPE-$TASK_ID"
START_TIME=$(date +%s000)

echo "[1/4] 初始化隔离环境 (Git Worktree)..."
cd "$REPO_PATH"

# 检查分支是否存在，不存在则基于 main 创建，存在则直接 checkout
if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
    echo "分支 $BRANCH_NAME 已存在，添加 worktree..."
    git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
else
    # 尝试获取 origin/main 或本地 main 作为基准
    if git show-ref --verify refs/remotes/origin/main >/dev/null 2>&1; then
        echo "基于 origin/main 创建分支 $BRANCH_NAME 并添加 worktree..."
        git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" "origin/main"
    elif git show-ref --verify refs/heads/main >/dev/null 2>&1; then
        echo "基于本地 main 创建分支 $BRANCH_NAME 并添加 worktree..."
        git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" "main"
    else
        echo "未找到 main 分支，基于当前分支创建并添加 worktree..."
        git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME"
    fi
fi

echo "[2/4] 安装基础依赖 (如果在 JS/TS 环境)..."
cd "$WORKTREE_DIR"
if [ -f "package.json" ]; then
    if [ -f "pnpm-lock.yaml" ]; then
        pnpm install || echo "pnpm install 警告（可忽略）"
    elif [ -f "yarn.lock" ]; then
        yarn install || echo "yarn install 警告（可忽略）"
    else
        npm install || echo "npm install 警告（可忽略）"
    fi
fi

echo "[3/4] 构建并启动 Agent Tmux 会话..."
PROMPT_CONTENT=$(cat "$PROMPT_FILE")
# 转义单引号以安全传递给 tmux send-keys
ESCAPED_PROMPT=$(echo "$PROMPT_CONTENT" | sed "s/'/'\\\\''/g")

# 创建新的 tmux detached 会话
tmux new-session -d -s "$TMUX_SESSION" -c "$WORKTREE_DIR"

if [ "$AGENT_TYPE" == "codex" ]; then
    # 启动 Codex
    tmux send-keys -t "$TMUX_SESSION" "codex --model $MODEL -c \"model_reasoning_effort=high\" --dangerously-bypass-approvals-and-sandbox '$ESCAPED_PROMPT'" Enter
elif [ "$AGENT_TYPE" == "claude" ]; then
    # 启动 Claude Code
    tmux send-keys -t "$TMUX_SESSION" "claude --model $MODEL --dangerously-skip-permissions -p '$ESCAPED_PROMPT'" Enter
elif [ "$AGENT_TYPE" == "gemini" ]; then
    # 启动 Gemini CLI
    tmux send-keys -t "$TMUX_SESSION" "gemini --model $MODEL -p '$ESCAPED_PROMPT'" Enter
else
    echo "未知的 Agent 类型: $AGENT_TYPE"
    exit 1
fi

echo "[4/4] 注册任务状态到 active-tasks.json..."

# 使用 python 脚本安全更新 JSON
python3 "$CLAWDBOT_DIR/scripts/register_task.py" "$TASK_ID" "$TMUX_SESSION" "$AGENT_TYPE" "$MODEL" "$REPO_PATH" "$WORKTREE_DIR" "$BRANCH_NAME" "$START_TIME"

echo "✅ 任务 $TASK_ID 已成功拉起。"
echo "Tmux Session: $TMUX_SESSION"
echo "你可以通过命令 \`tmux attach -t $TMUX_SESSION\` 查看 Agent 执行过程。"
