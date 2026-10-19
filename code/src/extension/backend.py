"""JSON bridge for the local VS Code paper-history panel. No network services."""
import difflib
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

MAX_BYTES = 2 * 1024 * 1024

class Backend:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.papers = self.root / 'papers'
        spec = importlib.util.spec_from_file_location('paper_history', self.root / '.latex-tools/paper_history.py')
        self.h = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.h)

    def repo(self, name):
        if not isinstance(name, str) or name in ('', '.', '..') or '/' in name or '\\' in name:
            raise ValueError('无效的论文目录。')
        repo = self.papers / name
        if repo.is_symlink() or repo.resolve().parent != self.papers.resolve() or not repo.is_dir():
            raise ValueError('论文目录不在配置的 papers 中。')
        if not self.h.managed(repo):
            raise ValueError('该论文尚未启用自动历史，请等待下次自动记录。')
        return repo

    def git(self, repo, *args, check=True):
        result = subprocess.run(['git', '-c', 'safe.directory=' + str(repo), '-C', str(repo),
            *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        if check and result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', 'replace').strip())
        return result

    def commit(self, repo, sha):
        if not isinstance(sha, str) or not re.fullmatch(r'[a-f0-9]{40}', sha):
            raise ValueError('请选择有效版本。')
        self.git(repo, 'cat-file', '-e', sha + '^{commit}')
        # Only expose versions belonging to this paper's active history.
        self.git(repo, 'merge-base', '--is-ancestor', sha, 'HEAD')
        return sha

    def path(self, repo, name):
        if not isinstance(name, str) or '\x00' in name or '\\' in name:
            raise ValueError('无效文件路径。')
        parts = PurePosixPath(name)
        if parts.is_absolute() or not parts.parts or any(p in ('.git', '..') for p in parts.parts):
            raise ValueError('文件路径超出论文目录。')
        path = repo / name
        try:
            path.resolve().relative_to(repo.resolve())
        except ValueError:
            raise ValueError('不允许读取论文目录外的文件。')
        if any(p.is_symlink() for p in [path, *path.parents] if p != repo.parent):
            raise ValueError('不预览符号链接。')
        return path

    def names(self, data):
        return [x.decode('utf-8', 'replace') for x in data.split(b'\0') if x]

    def files(self, repo, sha):
        old = set(self.names(self.git(repo, 'ls-tree', '-r', '--name-only', '-z', sha).stdout))
        current = set(self.names(self.git(repo, 'ls-files', '-z', '--cached', '--others', '--exclude-standard').stdout))
        changed = set(self.names(self.git(repo, 'diff', '--no-renames', '--name-only', '-z', sha, '--').stdout))
        changed |= current - old
        return [{'path': f, 'changed': f in changed,
            'status': '新增' if f not in old else ('删除' if not (repo / f).exists() else '修改') if f in changed else '一致'}
            for f in sorted(old | current)]

    def content(self, repo, sha, name):
        path = self.path(repo, name)
        entry = self.git(repo, 'ls-tree', '-z', sha, '--', name).stdout
        old_exists = bool(entry)
        old = b''
        if old_exists:
            header, actual = entry.rstrip(b'\0').split(b'\t', 1)
            mode, kind, oid = header.split()
            if actual.decode('utf-8') != name or kind != b'blob' or mode == b'120000':
                raise ValueError('不预览目录或符号链接。')
            if int(self.git(repo, 'cat-file', '-s', oid.decode()).stdout) > MAX_BYTES:
                return {'binary': True, 'reason': '文件超过 2 MB，请在原项目中查看。'}
            old = self.git(repo, 'cat-file', 'blob', oid.decode()).stdout
        if path.exists() and (not path.is_file() or path.stat().st_size > MAX_BYTES):
            return {'binary': True, 'reason': '文件超过 2 MB 或不是普通文件。'}
        current = path.read_bytes() if path.exists() else b''
        try:
            if b'\0' in old or b'\0' in current:
                raise UnicodeError()
            before, after = old.decode('utf-8-sig'), current.decode('utf-8-sig')
        except UnicodeError:
            return {'binary': True, 'reason': '图片、PDF 或非 UTF-8 文件：已记录版本，不显示文字差异。'}
        lines = list(difflib.unified_diff(before.splitlines(), after.splitlines(),
            fromfile='所选历史版本', tofile='当前已保存内容', lineterm=''))
        return {'binary': False, 'before': before, 'after': after, 'oldExists': old_exists,
            'currentExists': path.is_file(), 'diff': '\n'.join(lines),
            'additions': sum(x.startswith('+') and not x.startswith('+++') for x in lines),
            'deletions': sum(x.startswith('-') and not x.startswith('---') for x in lines)}

    def run(self, req):
        action = req.get('action')
        if action == 'projects':
            return [{'name': p.name} for p in self.h.projects(self.papers) if self.h.managed(p)]
        repo = self.repo(req.get('project'))
        if action == 'history':
            offset = max(0, int(req.get('offset', 0)))
            raw = self.git(repo, 'log', '--show-notes=paper-history', '--max-count=51',
                '--skip=' + str(offset), '--format=%H%x1f%aI%x1f%s%x1f%N%x1e').stdout.decode('utf-8', 'replace')
            rows = []
            for row in raw.split('\x1e'):
                if row.strip():
                    sha, date, message, note = row.lstrip('\n').rstrip('\n').split('\x1f', 3)
                    rows.append({'sha': sha, 'date': date, 'message': message, 'label': note.strip()})
            return {'versions': rows[:50], 'more': len(rows) > 50,
                'dirty': bool(self.git(repo, 'status', '--porcelain').stdout)}
        if action == 'snapshot':
            label = str(req.get('label', '')).strip()[:200]
            if not label:
                raise ValueError('请输入版本名称。')
            with self.h.lock(self.papers):
                return {'saved': self.h.snapshot(repo, '里程碑：' + label)}
        sha = self.commit(repo, req.get('sha'))
        if action == 'details':
            return {'files': self.files(repo, sha)}
        if action == 'content':
            return self.content(repo, sha, req.get('file'))
        if action == 'rename':
            label = str(req.get('label', '')).strip()[:200]
            if not label:
                raise ValueError('请输入版本名称。')
            with self.h.lock(self.papers):
                self.git(repo, 'notes', '--ref=paper-history', 'add', '-f', '-m', label, sha)
            return {'label': label}
        if action == 'restore':
            with self.h.lock(self.papers):
                return {'backup': self.h.restore(repo, sha)}
        raise ValueError('未知操作。')

if __name__ == '__main__':
    try:
        request = json.load(sys.stdin)
        print(json.dumps({'ok': True, 'data': Backend(request['root']).run(request)}, ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({'ok': False, 'error': str(exc)}, ensure_ascii=False))
        sys.exit(1)
