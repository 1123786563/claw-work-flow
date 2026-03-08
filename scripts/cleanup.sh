#!/bin/bash

# 每日清理脚本 - 清理已完成的任务和 orphaned worktrees

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

CLAWDBOT_ROOT="${CLAWDBOT_ROOT:-$HOME/clawdbot}"
WORKSPACE="$CLAWDBOT_ROOT"
TASKS_FILE="${ACTIVE_TASKS_FILE:-$WORKSPACE/active-tasks.json}"
WORKTREES_DIR="${WORKTREE_BASE:-$WORKSPACE/worktrees}"

echo "🧹 Starting cleanup..."

# 归档已完成的任务 (使用 .env 配置)
RETENTION_DAYS="${TASK_RETENTION_DAYS:-7}"
SEVEN_DAYS_AGO=$(date -v-"${RETENTION_DAYS}"d +%s 2>/dev/null || date -d "${RETENTION_DAYS} days ago" +%s)

TEMP_FILE=$(mktemp)
jq --argjson cutoff "$SEVEN_DAYS_AGO" \
   '.history += [.tasks[] | select(.status == "done" and .completedAt < $cutoff)] |
    .tasks = [.tasks[] | select(.status != "done" or .completedAt >= $cutoff)]' \
   "$TASKS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$TASKS_FILE"

echo "  📦 Archived old tasks (older than $RETENTION_DAYS days)"

# 清理 orphaned worktrees
echo "  Cleaning worktrees..."
for worktree in "$WORKTREES_DIR"/*; do
  if [ -d "$worktree" ]; then
    TASK_ID=$(basename "$worktree")
    BRANCH="feat/$TASK_ID"
    # 检查本地分支或远程分支是否存在
    if ! git show-ref --quiet "$BRANCH" 2>/dev/null; then
      echo "    Removing orphaned worktree for task: $TASK_ID (branch $BRANCH not found)"
      git worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
    fi
  fi
done

# 清理过时的 worktree 元数据
git worktree prune

# 清理旧日志 (使用 .env 配置)
LOG_RETENTION="${LOG_RETENTION_DAYS:-30}"
find "$WORKSPACE/logs" -name "*.log" -mtime +"$LOG_RETENTION" -delete 2>/dev/null

echo "✅ Cleanup complete"
