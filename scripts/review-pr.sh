#!/bin/bash

# PR 自动审查脚本
# 使用 Claude 和 Gemini 进行代码审查

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_PATH="$SCRIPT_DIR/../.env"
if [ -f "$DOTENV_PATH" ]; then
    source "$DOTENV_PATH"
fi

PR_NUMBER="$1"
# 优先从环境变量获取， fallback 到 $HOME/clawdbot
WORKSPACE="${CLAWDBOT_ROOT:-$HOME/clawdbot}"

echo "🔍 开始审查 PR #$PR_NUMBER"

cd "$WORKSPACE"

# 获取 PR diff
DIFF=$(gh pr diff "$PR_NUMBER")

if [ -z "$DIFF" ]; then
  echo "  ⚠️ 未找到  PR #$PR_NUMBER"
  exit 1
fi

# 1. Claude Code 审查
echo "  🤖 Claude Code 正在审查..."
CLAUDE_REVIEW=$(claude --model "${CLAUDE_MODEL:-claude-3-5-sonnet-20241022}" \
  --dangerously-skip-permissions \
  -p "审查此 PR diff 的代码质量、最佳实践和潜在问题。
仅关注关键问题，跳过样式建议。

PR Diff:
$DIFF

输出格式:
- CRITICAL: [阻塞问题]
- SUGGESTIONS: [可选改进]
- APPROVED: [如果没有关键问题]")

# 发布评论
if echo "$CLAUDE_REVIEW" | grep -q "CRITICAL"; then
  gh pr comment "$PR_NUMBER" -b "### 🔴 Claude Code 代码审查\n\n$CLAUDE_REVIEW"
  echo "  ⚠️ Claude 发现了关键问题"
else
  gh pr comment "$PR_NUMBER" -b "### ✅ Claude Code 代码审查\n\n$CLAUDE_REVIEW"
  echo "  ✅ Claude 已批准"
fi

# 2. Gemini 审查
echo "  🤖 Gemini 正在审查..."
GEMINI_REVIEW=$(gemini -m "${GEMINI_MODEL:-gemini-2.0-flash-exp}" \
  -p "审查此 PR diff，重点关注安全性、可扩展性和边缘情况。
识别特定的漏洞或性能问题。

PR Diff:
$DIFF

输出格式:
- SECURITY: [安全问题]
- PERFORMANCE: [性能问题]
- APPROVED: [如果没有问题]")

if echo "$GEMINI_REVIEW" | grep -qi "security\|performance"; then
  gh pr comment "$PR_NUMBER" -b "### 🔵 Gemini 审查\n\n$GEMINI_REVIEW"
  echo "  ⚠️ Gemini 发现了问题"
else
  gh pr comment "$PR_NUMBER" -b "### ✅ Gemini 审查\n\n$GEMINI_REVIEW"
  echo "  ✅ Gemini 已批准"
fi

echo "✅ PR #$PR_NUMBER 审查完成"