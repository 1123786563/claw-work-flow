#!/bin/bash
# -----------------------------------------------------------------------------
# validate-ui.sh
# 自动化 UI 验证：检测变更、启动本地环境、截屏并上报。
# -----------------------------------------------------------------------------

set -e

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

TASK_ID=$1
WORKTREE_DIR=$2
PR_NUMBER=$3

if [[ -z "$TASK_ID" || -z "$WORKTREE_DIR" || -z "$PR_NUMBER" ]]; then
    echo "用法: $0 <task_id> <worktree_dir> <pr_number>"
    exit 1
fi

CLAWDBOT_DIR="${CLAWDBOT_ROOT:-$HOME/clawdbot}"
SCREENSHOT_DIR="${LOG_DIR:-$CLAWDBOT_DIR/logs}/screenshots/$TASK_ID"
mkdir -p "$SCREENSHOT_DIR"

echo "正在验证任务 $TASK_ID 的 UI 变更..."
cd "$WORKTREE_DIR"

# 1. 检测 UI 文件变更 (与 main 比较)
# 修正：在 worktree 中通常需要明确指定对比的分支
UI_CHANGES=$(git diff --name-only origin/main | grep -E "\.(tsx|jsx|css|scss|html)$" || true)

if [[ -z "$UI_CHANGES" ]]; then
    echo "未检测到 UI 变更。跳过截图步骤。"
    exit 0
fi

echo "检测到以下 UI 变更:"
echo "$UI_CHANGES"

# 2. 尝试启动本地开发服务器
echo "正在启动本地开发服务器..."
# 这里根据项目实际情况调整启动命令。默认尝试 pnpm dev, npm run dev 等。
DEV_PORT="${DEV_SERVER_PORT:-3000}"
if [ -f "package.json" ]; then
    (pnpm dev || npm run dev || yarn dev) > /dev/null 2>&1 &
    DEV_SERVER_PID=$!
    
    # 等待服务器启动 (可以根据具体项目通过 curl 检查端口)
    echo "等待服务器启动 (PID: $DEV_SERVER_PID)..."
    sleep 10
fi

# 3. 运行截图脚本
SCREENSHOT_FILE="$SCREENSHOT_DIR/validation.png"
node "$CLAWDBOT_DIR/scripts/capture-screenshot.js" "http://localhost:$DEV_PORT" "$SCREENSHOT_FILE" || echo "截图捕获出现问题，请检查。"

# 4. 上报结果到 PR (添加一条评论)
if [ -f "$SCREENSHOT_FILE" ]; then
    gh pr comment "$PR_NUMBER" --body "🎨 **UI Validation Screenshot**
    
    检测到 UI 变更，已自动捕获本地截图并保存至: `$SCREENSHOT_FILE`。
    请审核员在本地查看确认（或配置 OSS/S3 以预览图）。"
else
    gh pr comment "$PR_NUMBER" --body "⚠️ **UI Validation Failed**
    
    检测到 UI 变更，但在尝试捕获截图时遇到问题。请手动验证样式。"
fi

# 清理
if [[ ! -z "$DEV_SERVER_PID" ]]; then
    echo "正在关闭开发服务器 (PID: $DEV_SERVER_PID)..."
    kill $DEV_SERVER_PID || true
fi

echo "✅ UI 验证完成。"
