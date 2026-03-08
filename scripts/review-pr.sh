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

echo "🔍 Starting code review for PR #$PR_NUMBER"

cd "$WORKSPACE"

# 获取 PR diff
DIFF=$(gh pr diff "$PR_NUMBER")

if [ -z "$DIFF" ]; then
  echo "  ⚠️ No diff found for PR #$PR_NUMBER"
  exit 1
fi

# 1. Claude Code 审查
echo "  🤖 Claude Code reviewing..."
CLAUDE_REVIEW=$(claude --model "${CLAUDE_MODEL:-claude-3-5-sonnet-20241022}" \
  --dangerously-skip-permissions \
  -p "Review this PR diff for code quality, best practices, and potential issues.
Be specific about critical issues only. Skip style suggestions.

PR Diff:
$DIFF

Output format:
- CRITICAL: [blocking issues]
- SUGGESTIONS: [optional improvements]
- APPROVED: [if no critical issues]")

# 发布评论
if echo "$CLAUDE_REVIEW" | grep -q "CRITICAL"; then
  gh pr comment "$PR_NUMBER" -b "### 🔴 Claude Code Review\n\n$CLAUDE_REVIEW"
  echo "  ⚠️ Claude found critical issues"
else
  gh pr comment "$PR_NUMBER" -b "### ✅ Claude Code Review\n\n$CLAUDE_REVIEW"
  echo "  ✅ Claude approved"
fi

# 2. Gemini 审查
echo "  🤖 Gemini reviewing..."
GEMINI_REVIEW=$(gemini -m "${GEMINI_MODEL:-gemini-2.0-flash-exp}" \
  -p "Review this PR diff focusing on security, scalability, and edge cases.
Identify specific vulnerabilities or performance issues.

PR Diff:
$DIFF

Output format:
- SECURITY: [security concerns]
- PERFORMANCE: [performance issues]
- APPROVED: [if no concerns]")

if echo "$GEMINI_REVIEW" | grep -qi "security\|performance"; then
  gh pr comment "$PR_NUMBER" -b "### 🔵 Gemini Review\n\n$GEMINI_REVIEW"
  echo "  ⚠️ Gemini found issues"
else
  gh pr comment "$PR_NUMBER" -b "### ✅ Gemini Review\n\n$GEMINI_REVIEW"
  echo "  ✅ Gemini approved"
fi

echo "✅ Reviews complete for PR #$PR_NUMBER"
