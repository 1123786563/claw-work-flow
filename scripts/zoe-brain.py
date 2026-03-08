#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# ~/brain.py
# Orchestrator (Zoe) 核心逻辑：从 Obsidian 提取业务上下文并自动拉起 Agent。
# -----------------------------------------------------------------------------

import os
import json
import argparse
import subprocess
from pathlib import Path

# 配置加载
CLAWDBOT_ROOT = os.environ.get('CLAWDBOT_ROOT', os.path.expanduser("~/clawdbot"))
CONFIG_PATH = os.path.join(CLAWDBOT_ROOT, "config.json")
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

OBSIDIAN_VAULT = Path(config["obsidian_vault_path"])
SCRIPTS_DIR = Path(os.path.join(CLAWDBOT_ROOT, "scripts"))

def search_obsidian_context(goal):
    """
    在 Obsidian 仓库中搜索与目标相关的关键词。
    简单起见，使用 grep 或 Python 遍历查找包含目标关键字的最新 Markdown 文件。
    """
    print(f"正在 Obsidian 库中搜索 '{goal}' 的业务上下文...")
    relevant_notes = []
    
    # 获取关键字列表 (拆分目标字符串)
    keywords = goal.split()
    
    # 查找最近 30 天修改过的 Markdown 文件，或者包含关键字的文件
    # 这里我们简化为直接遍历，实际可以根据需求优化
    for note in OBSIDIAN_VAULT.rglob("*.md"):
        try:
            content = note.read_text()
            if any(kw.lower() in content.lower() for kw in keywords):
                relevant_notes.append((note, content))
        except:
            continue
            
    # 只返回最相关的 3 个笔记内容，避免 Context 爆炸
    return relevant_notes[:3]

def synthesize_prompt(goal, context_notes):
    """
    合成最终给 Coding Agent 的 Prompt。
    理想情况下这里调用一次 LLM (Gemini/Claude) 进行 Summarization 和 Specs 生成。
    """
    business_context = "

".join([f"--- 来源: {note[0].name} ---
{note[1][:2000]}..." for note in context_notes])
    
    # 构建 Mega-Prompt 模板
    prompt_template = f"""
# Task: {goal}

## Business Context (From Obsidian Notes)
{business_context if business_context else "没有找到具体的背景笔记，请根据基础最佳实践执行。"}

## Objective
你现在是团队的一员，负责实现以下功能: {goal}。

## Technical Requirements
- 必须遵循项目现有的架构风格和命名规范。
- 如果涉及 UI 变更，确保使用项目中定义的 Tailwind/CSS 变量。
- 如果涉及 API 修改，确保处理错误边界并更新相关的类型定义。

## Definition of Done
- 实现功能逻辑。
- 所有的单元测试必须通过。
- 代码风格符合项目 Lint 规范。
- 提交 PR 并提供必要的说明。

现在请开始分析代码库并执行任务。
"""
    return prompt_template

def main():
    parser = argparse.ArgumentParser(description="Zoe Orchestrator: Business Context to Coding Agent")
    parser.add_argument("--goal", required=True, help="你的高层目标 (例如: '实现 Stripe 退款功能')")
    parser.add_argument("--project", required=True, help="项目标识名 (对应 config.json 中的 project_mappings)")
    parser.add_argument("--task-id", help="手动指定任务 ID，若不指定则根据 goal 自动生成")
    parser.add_argument("--agent", choices=["claude", "codex"], help="强制指定 Agent 类型")
    
    args = parser.parse_args()
    
    # 1. 解析基础信息
    project_path = config["project_mappings"].get(args.project)
    if not project_path:
        print(f"❌ 错误: 找不到项目 {args.project} 的映射。请检查 config.json。")
        return

    task_id = args.task_id or f"{args.project}-{args.goal.lower().replace(' ', '-')[:20]}"
    
    # 2. 提取业务上下文
    notes = search_obsidian_context(args.goal)
    
    # 3. 合成 Prompt
    final_prompt = synthesize_prompt(args.goal, notes)
    
    # 4. 保存 Prompt
    prompts_dir = Path(os.path.join(CLAWDBOT_ROOT, "prompts"))
    prompts_dir.mkdir(parents=True, exist_ok=True)
    prompt_file = prompts_dir / f"{task_id}.md"
    prompt_file.write_text(final_prompt)
    print(f"✅ 已生成 Prompt 文件: {prompt_file}")
    
    # 5. 决定 Agent 类型和模型
    # 逻辑简化：如果包含 'UI', 'Button', 'Style' 等关键词，选 Claude；否则选 Codex。
    agent_info = config["default_agents"]["logic"]
    if any(k in args.goal.lower() for k in ["ui", "style", "css", "frontend", "页面"]):
        agent_info = config["default_agents"]["ui"]
    
    agent_type = args.agent or agent_info["name"]
    model_name = agent_info["model"]
    
    # 6. 调用 spawn-agent.sh
    spawn_cmd = [
        str(SCRIPTS_DIR / "spawn-agent.sh"),
        "--task-id", task_id,
        "--agent", agent_type,
        "--model", model_name,
        "--repo", project_path,
        "--prompt-file", str(prompt_file)
    ]
    
    print(f"🚀 正在拉起 {agent_type} Agent (Task ID: {task_id})...")
    subprocess.run(spawn_cmd)
    print(f"
✨ Zoe 已完成任务分发。请通过 'tmux attach -t {agent_type}-{task_id}' 关注进度。")

if __name__ == "__main__":
    main()
