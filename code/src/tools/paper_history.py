#!/usr/bin/env python3
"""Local, independent paper repositories. Run inside the latex container."""
import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
IGNORE = '''
# Managed LaTeX history: keep source PDFs and supplied .bbl files.
output/
.tmp/
.cache/
__pycache__/
*.aux
*.log
*.fls
*.fdb_latexmk
*.synctex.gz
*.synctex
*.toc
*.out
*.blg
*.bcf
*.run.xml
*.nav
*.snm
*.vrb
*.lof
*.lot
*.xdv
*.dvi
'''

def now():
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8)))

def git(repo, *args, check=True):
    result = subprocess.run(['git', '-c', 'safe.directory=' + str(repo.resolve()),
        '-C', str(repo), *args], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=180)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Git 操作失败')
    return result

@contextlib.contextmanager
def lock(papers):
    if (papers.parent / '.latex-tools' / '.deployment-in-progress.json').exists():
        raise RuntimeError('运行组件正在更新，请稍后重试历史操作。')
    state = papers.parent / '.tmp' / 'paper-history'
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'operation.lock').open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('另一个历史操作正在运行，请稍后重试。')
        if (papers.parent / '.latex-tools' / '.deployment-in-progress.json').exists():
            raise RuntimeError('运行组件正在更新，请稍后重试历史操作。')
        yield

def projects(papers):
    return sorted((p for p in papers.iterdir() if p.is_dir() and not p.is_symlink()
        and not p.name.startswith('.') and p.name != 'output'), key=lambda p: p.name.lower())

def managed(repo):
    return (repo / '.git').is_dir() and git(repo, 'config', '--local', '--get',
        'latexHistory.managed', check=False).stdout.strip() == 'true'

def initialize(repo):
    if (repo / '.git').exists():
        if not managed(repo):
            raise RuntimeError('已有非本工具管理的 Git 仓库，已跳过以保留原有工作流。')
        return
    # Do not wrap a pre-existing nested repository or an unrelated directory.
    has_tex = False
    for base, dirs, files in os.walk(repo):
        if '.git' in dirs or '.git' in files:
            raise RuntimeError('目录包含已有 Git 仓库，已跳过。')
        dirs[:] = [d for d in dirs if d not in ('output', '.tmp', '.cache', '__pycache__')]
        has_tex |= any(f.lower().endswith('.tex') for f in files)
    if not has_tex:
        raise RuntimeError('没有找到 .tex 源文件，已跳过。')
    parent_git = git(repo.parent, 'rev-parse', '--show-toplevel', check=False)
    if parent_git.returncode == 0:
        raise RuntimeError('上级目录已有 Git 仓库，已跳过。')
    git(repo, 'init', '-b', 'main')
    for key, value in [('user.name', 'Local LaTeX History'),
        ('user.email', 'latex-history@localhost'), ('core.autocrlf', 'false'),
        ('core.filemode', 'false'), ('core.quotepath', 'false')]:
        git(repo, 'config', '--local', key, value)
    with (repo / '.git' / 'info' / 'exclude').open('a', encoding='utf-8') as f:
        f.write(IGNORE)
    git(repo, 'config', '--local', 'latexHistory.managed', 'true')

def ready(repo):
    if not managed(repo):
        raise RuntimeError('这个项目尚未启用本工具的历史记录。')
    dotgit = repo / '.git'
    for name in ('index.lock', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
                 'rebase-merge', 'rebase-apply', 'BISECT_LOG'):
        if (dotgit / name).exists():
            raise RuntimeError('Git 正在执行其他操作，已跳过：' + name)
    if git(repo, 'symbolic-ref', '-q', 'HEAD', check=False).returncode:
        raise RuntimeError('当前处于 detached HEAD，已跳过。')
    if git(repo, 'diff', '--cached', '--quiet', check=False).returncode:
        raise RuntimeError('存在手动暂存的修改，已跳过；请先提交或取消暂存。')

def snapshot(repo, label=None):
    ready(repo)
    dirty = bool(git(repo, 'status', '--porcelain', '--untracked-files=all').stdout)
    initial = git(repo, 'rev-parse', '--verify', 'HEAD', check=False).returncode != 0
    if not dirty and not label and not initial:
        return 'unchanged'
    git(repo, 'add', '--all', '--', '.')
    message = label or ('初始版本' if initial else '自动保存') + ' · ' + now().isoformat(timespec='seconds')
    git(repo, 'commit', '--allow-empty', '-m', message)
    return git(repo, 'rev-parse', '--short', 'HEAD').stdout.strip()

def restore(repo, target):
    ready(repo)
    commit = git(repo, 'rev-parse', '--verify', target + '^{commit}').stdout.strip()
    # Preserve all saved, non-ignored edits before changing the working tree.
    snapshot(repo, '恢复前备份 · ' + now().isoformat(timespec='seconds'))
    backup = git(repo, 'rev-parse', 'HEAD').stdout.strip()
    tag = 'before-restore-' + now().strftime('%Y%m%d-%H%M%S-%f')
    git(repo, 'tag', tag, backup)
    git(repo, 'restore', '--source=' + commit, '--staged', '--worktree', '--', '.')
    git(repo, 'commit', '--allow-empty', '-m', '恢复到 ' + commit[:12] + ' · ' + now().isoformat(timespec='seconds'))
    return backup

def sweep(papers):
    results = []
    with lock(papers):
        for repo in projects(papers):
            try:
                initialize(repo)
                result = {'project': repo.name, 'result': snapshot(repo)}
            except Exception as exc:
                result = {'project': repo.name, 'error': str(exc)}
            results.append(result)
        report = {'time': now().isoformat(), 'projects': results}
        destination = papers.parent / '.tmp' / 'paper-history' / 'last-run.json'
        temp = destination.with_suffix('.new')
        temp.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        temp.replace(destination)
    print(json.dumps(report, ensure_ascii=False))
    return int(any('error' in r for r in results))

def choose(items, prompt):
    answer = input(prompt).strip()
    if not answer:
        return None
    try:
        index = int(answer) - 1
        if 0 <= index < len(items):
            return items[index]
    except ValueError:
        pass
    raise RuntimeError('请输入列表中的编号。')

def menu(papers):
    while True:
        repos = projects(papers)
        print('\n论文历史（文件保存在本机；不会上传 GitHub）')
        for i, repo in enumerate(repos, 1):
            print(f'{i:2}. {repo.name}')
        try:
            repo = choose(repos, '\n论文编号（回车退出）：')
            if repo is None:
                return 0
            print('\n1. 保存命名版本，如“投稿前”\n2. 查看历史\n3. 比较并恢复旧版本')
            action = input('操作编号：').strip()
            if action == '1':
                label = input('版本名称：').strip()
                if label:
                    with lock(papers):
                        initialize(repo)
                        print('已保存：' + snapshot(repo, '里程碑：' + label))
            elif action in ('2', '3'):
                if not managed(repo):
                    raise RuntimeError('请先保存一个命名版本，或等待自动记录。')
                log = git(repo, 'log', '-100', '--date=iso-local',
                    '--format=%H%x09%ad%x09%s').stdout.splitlines()
                for i, row in enumerate(log, 1):
                    sha, date, title = row.split('\t', 2)
                    print(f'{i:3}. {sha[:10]}  {date}  {title}')
                if action == '3':
                    row = choose(log, '\n恢复到哪个编号（回车取消）：')
                    if row is None:
                        continue
                    sha = row.split('\t')[0]
                    print(git(repo, 'diff', '--stat', sha, '--', '.').stdout)
                    print('当前已保存的源码会先备份，再恢复所选版本；PDF 请恢复后重新编译。')
                    if input('输入 RESTORE 确认恢复，其他输入取消：').strip() == 'RESTORE':
                        with lock(papers):
                            backup = restore(repo, sha)
                        print('已恢复。恢复前备份：' + backup[:12])
            else:
                print('已取消。')
        except Exception as exc:
            print('操作未完成：' + str(exc))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['sweep', 'menu'])
    parser.add_argument('--papers-root', type=Path, default=ROOT / 'papers')
    args = parser.parse_args()
    os.environ['TZ'] = 'Asia/Shanghai'
    papers = args.papers_root.resolve()
    if not papers.is_dir():
        parser.error('论文目录不存在：' + str(papers))
    return sweep(papers) if args.command == 'sweep' else menu(papers)

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        print('\n已退出。')
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
