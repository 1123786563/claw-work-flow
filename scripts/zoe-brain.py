#!/usr/bin/env python3
"""
Orchestrator (Zoe) 核心逻辑：从 Obsidian 提取业务上下文并自动拉起 Agent。
"""

import os
import json
import argparse
import subprocess
from pathlib import Path

# 加载环境变量配置 (由父 shell 提供)
CLAWDBOT_ROOT = os.environ.get('CLAWDBOT_ROOT', os.path.expanduser("~/clawdbot"))
CONFIG_PATH = os.path.join(CLAWDBOT_ROOT, "config.json")

# 加载配置
with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

OBSIDIAN_VAULT = Path(config["obsidian_vault_path"])
SCRIPTS_DIR = Path(os.path.join(CLAWDBOT_ROOT, "scripts"))

def search_obsidian_context(goal):
    """搜索 Obsidian 业务上下文"""
    relevant_notes = []
    keywords = goal.split()
    if not OBSIDIAN_VAULT.exists():
        return []
    for note in OBSIDIAN_VAULT.rglob("*.md"):
        try:
            content = note.read_text()
            if any(kw.lower() in content.lower() for kw in keywords):
                relevant_notes.append((note, content))
        except:
            continue
    return relevant_notes[:3]

def synthesize_prompt(goal, context_notes):
    """合成最终 Prompt"""
    business_context = "\n\n".join([f"--- 来源: {note[0].name} ---\n{note[1][:2000]}..." for note in context_notes])
    return f"""
# Task: {goal}
## Business Context
{business_context if business_context else "没有找到业务笔记。"}
## Objective
实现功能: {goal}。
"""

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--goal", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--task-id")
    parser.add_argument("--agent")
    args = parser.parse_args()

    project_path = config["project_mappings"].get(args.project)
    if not project_path:
        print(f"❌ 找不到项目 {args.project}")
        return

    task_id = args.task_id or f"{args.project}-{args.goal.lower().replace(' ', '-')[:20]}"
    notes = search_obsidian_context(args.goal)
    final_prompt = synthesize_prompt(args.goal, notes)

    prompts_dir = Path(os.path.join(CLAWDBOT_ROOT, "prompts"))
    prompts_dir.mkdir(parents=True, exist_ok=True)
    prompt_file = prompts_dir / f"{task_id}.md"
    prompt_file.write_text(final_prompt)

    agent_info = config["default_agents"]["logic"]
    if any(k in args.goal.lower() for k in ["ui", "style", "css", "frontend"]):
        agent_info = config["default_agents"]["ui"]

    agent_type = args.agent or agent_info["name"]
    model_name = agent_info["model"]

    spawn_cmd = [
        str(SCRIPTS_DIR / "spawn-agent.sh"),
        "--task-id", task_id,
        "--agent", agent_type,
        "--model", model_name,
        "--repo", project_path,
        "--prompt-file", str(prompt_file)
    ]
    
    # 确保 CLAWDBOT_ROOT 在环境变量中供子进程使用
    env = os.environ.copy()
    env["CLAWDBOT_ROOT"] = CLAWDBOT_ROOT
    
    subprocess.run(spawn_cmd, env=env)
    print(f"✅ Zoe 已完成任务分发: {task_id}")

if __name__ == "__main__":
    main()
