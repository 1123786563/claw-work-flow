# 🤖 OpenClaw Agent Swarm

本地运行的 AI 代理群组系统，由 Zoe 协调器管理。

## 架构

```
┌─────────────┐
│    Zoe      │ ← 主协调器 (任务分析、模型选择、prompt 生成)
└──────┬──────┘
       │
       ├─────────────┬─────────────┐
       ▼             ▼             ▼
   ┌───────┐     ┌───────┐     ┌───────┐
   │Claude │     │Gemini │     │ ...   │ ← 专业 Agent
   └───┬───┘     └───┬───┘     └───┬───┘
       │             │             │
       └─────────────┴─────────────┘
                     │
       ┌─────────────▼─────────────┐
       │   tmux sessions + logs    │
       └─────────────┬─────────────┘
                     │
       ┌─────────────▼─────────────┐
       │   GitHub PR + CI/CD       │
       └─────────────┬─────────────┘
                     │
       ┌─────────────▼─────────────┐
       │   Auto Review (3 models)  │
       └───────────────────────────┘
```

## 目录结构

```
~/clawdbot/
├── active-tasks.json      # 任务注册表
├── README.md              # 本文件
├── scripts/
│   ├── spawn-agent.sh     # 启动 Agent
│   ├── check-agents.sh    # 监控循环 (每 10 分钟)
│   ├── review-pr.sh       # PR 审查
│   ├── zoe.sh             # Zoe 协调器
│   ├── cleanup.sh         # 清理脚本 (每日)
│   ├── notify.sh          # 通知发送 (Telegram/Discord/Slack)
│   ├── setup-cron.sh      # 配置定时任务
│   ├── remove-cron.sh     # 移除定时任务
│   └── auth/              # 认证模块
│       ├── db.sh          # 数据库管理
│       ├── user.sh        # 用户 CRUD 操作
│       └── test/          # 认证测试
├── prompts/
│   ├── zoe-scoping.md     # Zoe 任务分解模板
│   ├── codex-reviewer.md  # Claude 审查模板
│   └── gemini-reviewer.md # Gemini 审查模板
├── logs/                  # Agent 日志
└── worktrees/             # Git worktrees
```

## 快速开始

### 1. 启动任务 (通过 Zoe)

```bash
~/clawdbot/scripts/zoe.sh "添加用户登录功能"
```

### 2. 直接指定 Agent

```bash
~/clawdbot/scripts/spawn-agent.sh "my-task" "claude" "实现 JWT 认证..."
```

### 3. 查看任务状态

```bash
# 查看活跃任务
jq '.tasks[] | select(.status == "running")' ~/clawdbot/active-tasks.json

# 查看 tmux 会话
tmux list-sessions | grep -E "(claude|gemini)-"

# 查看日志
tail -f ~/clawdbot/logs/task-*.log
```

### 4. 手动运行监控

```bash
~/clawdbot/scripts/check-agents.sh
```

### 工作流

1. **任务接收** → Zoe 分析任务，选择合适 Agent
2. **启动 Agent** → 创建 worktree + tmux 会话
3. **开发** → Agent 编写代码、提交
4. **PR 创建** → Agent 自动创建 PR
5. **CI 运行** → GitHub Actions 自动测试
6. **自动审查** → Claude + Gemini 审查代码
7. **通知** → PR 就绪，等待人工合并
8. **清理** → 每日清理旧任务

## Cron 任务

```bash
# 配置定时任务（一键设置）
~/clawdbot/scripts/setup-cron.sh

# 查看已配置的 cron
crontab -l | grep clawdbot

# 移除定时任务
~/clawdbot/scripts/remove-cron.sh

# 定时任务说明:
# */10 * * * * ~/clawdbot/scripts/check-agents.sh  # 每10分钟监控
# 0 3 * * * ~/clawdbot/scripts/cleanup.sh          # 每日凌晨3点清理
```

## 通知配置

编辑 `~/clawdbot/.env`，配置你想要的通知渠道：

```bash
# Telegram 通知
TELEGRAM_BOT_TOKEN="your-bot-token"
TELEGRAM_CHAT_ID="your-chat-id"

# Discord 通知
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/xxx/xxx"

# Slack 通知
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx/xxx/xxx"
```

通知类型：
- `pr_ready` - PR 就绪，等待人工合并
- `ci_failed` - CI 测试失败
- `merged` - PR 已合并
- `crashed` - Agent 崩溃

手动发送通知：
```bash
~/clawdbot/scripts/notify.sh pr_ready task-xxx 123 "https://github.com/xxx/pull/123" "Ready for review"
```

## 配置

编辑 `~/clawdbot/active-tasks.json`:

```json
{
  "config": {
    "maxRetries": 3,           # 最大重试次数
    "checkIntervalMinutes": 10, # 监控间隔
    "agents": {
      "claude": { "model": "claude-opus-4-5-20251029" },
      "gemini": { "model": "gemini-2.5-pro" }
    }
  }
}
```

## 故障排查

### Agent 卡住

```bash
# 查看 tmux 会话
tmux attach -t claude-my-task

# 发送指令
tmux send-keys -t claude-my-task "Stop. Focus on the API layer." Enter

# 或重启
tmux kill-session -t claude-my-task
~/clawdbot/scripts/spawn-agent.sh "my-task" "claude" "新 prompt"
```

### 查看日志

```bash
# 实时查看
tail -f ~/clawdbot/logs/task-*.log

# 搜索错误
grep -r "ERROR" ~/clawdbot/logs/
```

### 任务状态异常

```bash
# 手动更新状态
jq '.tasks[] |= if .id == "my-task" then .status = "failed" else . end' \
  ~/clawdbot/active-tasks.json > tmp.json && mv tmp.json ~/clawdbot/active-tasks.json
```

## 最佳实践

1. **任务分解** - 大任务拆成小任务，每个任务专注一个功能
2. **明确 Prompt** - 包含具体文件路径、预期输出、约束条件
3. **及时审查** - PR 就绪后尽快 review，避免 Agent 等待
4. **定期清理** - cleanup.sh 每天运行，保持系统整洁
5. **日志归档** - 重要任务的日志定期备份

## 扩展

添加新 Agent 类型:

1. 在 `active-tasks.json` 添加配置
2. 在 `spawn-agent.sh` 添加启动逻辑
3. 在 `zoe.sh` 更新选择逻辑

---

## 更新日志

### 2026-03-08
- **逻辑修复**: 修复了任务协调逻辑中的重复执行问题,优化了Zoe协调器的agent选择算法

**生产力统计** (参考):

- 日均提交：50+ commits
- PR 创建速度：7 PRs / 30 分钟
- 自动化率：90%+ 小中型任务一键完成
