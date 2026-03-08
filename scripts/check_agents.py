#!/usr/bin/env python3
"""
监控与自愈脚本：检查 Agent 活跃状态、PR 及 CI 状态，并更新 JSON。
"""

import json
import subprocess
import os
import sys


def run_command(cmd_list, cwd=None):
    """执行命令并返回输出 (接收列表参数以避免 shell 注入)"""
    try:
        return subprocess.check_output(cmd_list, text=True, stderr=subprocess.STDOUT, cwd=cwd).strip()
    except subprocess.CalledProcessError:
        return None


def main():
    """主函数"""
    clawdbot_dir = os.environ.get('CLAWDBOT_ROOT', os.path.expanduser('~/clawdbot'))
    registry_file = os.path.join(clawdbot_dir, 'active-tasks.json')

    data = {'tasks': []}
    try:
        with open(registry_file, 'r') as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
                if 'tasks' not in data:
                    data['tasks'] = []
            elif isinstance(loaded, list):
                data['tasks'] = loaded
    except (json.JSONDecodeError, FileNotFoundError):
        print('注册表为空或损坏')
        sys.exit(0)

    updated_tasks = []
    for task in data.get('tasks', []):
        status = task.get('status', 'unknown')
        task_id = task.get('id')
        tmux_session = task.get('tmuxSession')
        branch = task.get('branch')
        worktree = task.get('worktree')

        if status in ['running', 'pr_created', 'failed']:
            # 检查 tmux session
            is_tmux_alive = run_command(['tmux', 'has-session', '-t', tmux_session]) is not None
            
            # 检查 worktree 目录是否存在
            if not worktree or not os.path.isdir(worktree):
                print(f'❌ 任务 {task_id} 的 worktree 目录不存在: {worktree}')
                task['status'] = 'crashed'
                task['note'] = 'Worktree missing'
                updated_tasks.append(task)
                continue

            # 检查 PR 信息
            pr_info_json = run_command(['gh', 'pr', 'list', '--head', branch, '--json', 'number,state,statusCheckRollup,url'], cwd=worktree)
            
            pr_info = None
            if pr_info_json:
                try:
                    prs = json.loads(pr_info_json)
                    if prs:
                        pr_info = prs[0]
                except:
                    pass

            # 状态演进
            if is_tmux_alive:
                if pr_info:
                    task['status'] = 'pr_created'
                    task['prNumber'] = pr_info['number']
                    task['prUrl'] = pr_info['url']
            else:
                if pr_info:
                    task['prNumber'] = pr_info['number']
                    task['prUrl'] = pr_info['url']
                    ci_status = pr_info.get('statusCheckRollup', [])
                    all_passed = True
                    has_failures = False
                    for check in ci_status:
                        if check.get('conclusion') == 'FAILURE':
                            has_failures = True
                            break
                        if check.get('status') != 'COMPLETED' or check.get('conclusion') != 'SUCCESS':
                            all_passed = False
                    
                    if has_failures:
                        task['status'] = 'failed'
                        task['note'] = 'CI Failed'
                    elif all_passed and ci_status:
                        task['status'] = 'completed'
                        task['note'] = 'CI Passed'
                    else:
                        task['status'] = 'pr_created'
                else:
                    if status == 'running':
                        task['status'] = 'crashed'
                        task['note'] = 'Agent died'
                        task['retryCount'] = task.get('retryCount', 0) + 1

            # 触发 UI 验证
            if task['status'] == 'pr_created' and not task.get('uiValidated'):
                print(f'>>> 正在为任务 {task_id} 触发 UI 验证...')
                validate_script = os.path.join(clawdbot_dir, 'scripts/validate-ui.sh')
                subprocess.run([validate_script, str(task_id), str(worktree), str(task.get("prNumber", ""))])
                task['uiValidated'] = True

            if pr_info and pr_info.get('state') == 'MERGED':
                if task.get('status') != 'merged':
                    # 发送合并通知
                    notify_script = os.path.join(clawdbot_dir, 'scripts/notify.sh')
                    subprocess.run([notify_script, 'merged', str(task_id),
                                   str(task.get('prNumber', '')),
                                   str(task.get('prUrl', '')),
                                   'PR has been merged successfully'])
                task['status'] = 'merged'

            # 发送 PR 就绪通知
            if task['status'] == 'completed' and not task.get('notified'):
                notify_script = os.path.join(clawdbot_dir, 'scripts/notify.sh')
                subprocess.run([notify_script, 'pr_ready', str(task_id),
                               str(task.get('prNumber', '')),
                               str(task.get('prUrl', '')),
                               'Ready for manual review and merge'])
                task['notified'] = True

            # 发送 CI 失败通知
            if task['status'] == 'failed' and not task.get('failedNotified'):
                notify_script = os.path.join(clawdbot_dir, 'scripts/notify.sh')
                subprocess.run([notify_script, 'ci_failed', str(task_id),
                               str(task.get('prNumber', '')),
                               str(task.get('prUrl', '')),
                               task.get('note', 'CI checks failed')])
                task['failedNotified'] = True

            # 发送崩溃通知
            if task['status'] == 'crashed' and not task.get('crashNotified'):
                notify_script = os.path.join(clawdbot_dir, 'scripts/notify.sh')
                subprocess.run([notify_script, 'crashed', str(task_id),
                               '', '', task.get('note', 'Agent crashed')])
                task['crashNotified'] = True

        updated_tasks.append(task)

    data['tasks'] = updated_tasks
    with open(registry_file, 'w') as f:
        json.dump(data, f, indent=2)

    print('✅ Monitor Loop 同步完成。')


if __name__ == '__main__':
    main()