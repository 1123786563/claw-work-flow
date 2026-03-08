#!/usr/bin/env python3
"""
任务注册脚本：用于注册任务状态到 active-tasks.json
"""

import json
import os
import sys


def register_task(task_id, tmux_session, agent_type, model, repo_path, worktree_dir, branch_name, start_time):
    """
    注册任务到 JSON 文件
    
    Args:
        task_id: 任务ID
        tmux_session: tmux会话名
        agent_type: 代理类型
        model: 模型名
        repo_path: 仓库路径
        worktree_dir: 工作树目录
        branch_name: 分支名
        start_time: 开始时间
    """
    clawdbot_root = os.environ.get('CLAWDBOT_ROOT', os.path.expanduser('~/clawdbot'))
    registry_file = os.path.expanduser(os.path.join(clawdbot_root, 'active-tasks.json'))
    
    task_data = {
        'id': task_id,
        'tmuxSession': tmux_session,
        'agent': agent_type,
        'model': model,
        'repo': os.path.basename(repo_path),
        'worktree': worktree_dir,
        'branch': branch_name,
        'startedAt': int(start_time),
        'status': 'running',
        'notifyOnComplete': True
    }

    # 读取现有数据
    data = {'tasks': []}
    if os.path.exists(registry_file) and os.path.getsize(registry_file) > 0:
        try:
            with open(registry_file, 'r') as f:
                loaded = json.load(f)
                if isinstance(loaded, dict):
                    data = loaded
                    if 'tasks' not in data:
                        data['tasks'] = []
                elif isinstance(loaded, list):
                    data['tasks'] = loaded
        except json.JSONDecodeError:
            pass

    # 如果已经存在同 id，则更新；否则追加
    updated = False
    for i, t in enumerate(data['tasks']):
        if t.get('id') == task_id:
            data['tasks'][i] = task_data
            updated = True
            break
    if not updated:
        data['tasks'].append(task_data)

    # 写入文件
    with open(registry_file, 'w') as f:
        json.dump(data, f, indent=2)


def main():
    """主函数，从命令行参数获取任务信息"""
    if len(sys.argv) != 9:
        print("用法: python3 register_task.py <task_id> <tmux_session> <agent_type> <model> <repo_path> <worktree_dir> <branch_name> <start_time>")
        sys.exit(1)
    
    task_id = sys.argv[1]
    tmux_session = sys.argv[2]
    agent_type = sys.argv[3]
    model = sys.argv[4]
    repo_path = sys.argv[5]
    worktree_dir = sys.argv[6]
    branch_name = sys.argv[7]
    start_time = sys.argv[8]
    
    register_task(task_id, tmux_session, agent_type, model, repo_path, worktree_dir, branch_name, start_time)
    print(f"✅ 任务 {task_id} 已成功注册。")


if __name__ == '__main__':
    main()