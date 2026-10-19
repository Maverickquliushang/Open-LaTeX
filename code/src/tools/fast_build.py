#!/usr/bin/env python3
"""Compile a mounted LaTeX project on the container filesystem.

Only a disposable source mirror is synchronized/deleted. Manuscripts are never
edited. Publish a complete native PDF first, then atomically copy it to /work.
"""
import argparse
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid

CACHE = Path('/opt/latex-build/.cache')
WORKSPACE = Path('/work')
SKIP_DIRS = {'output', '.tmp', '.cache', '.git', '.latex-tools', '__pycache__'}
TEXT_SUFFIXES = {'.tex', '.bib', '.sty', '.cls', '.bst', '.cfg', '.def', '.clo'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_bytes() == data:
        return False
    temporary = path.with_name(path.name + '.fast-build-tmp')
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def json_write(path, value):
    atomic_write(path, (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode())


def mirror_project(source, mirror, manifest_file):
    old = json.loads(manifest_file.read_text()) if manifest_file.exists() else {}
    current = {}
    copied = 0
    for directory, dirs, files in os.walk(source, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS
                         and not (Path(directory) / d).is_symlink())
        for filename in sorted(files):
            src = Path(directory) / filename
            rel = src.relative_to(source)
            if filename.endswith('.fast-build-tmp'):
                continue
            stat = src.stat()
            info = {'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns}
            content = None
            if src.suffix.lower() in TEXT_SUFFIXES or filename in {'.latexmkrc', 'latexmkrc'}:
                content = src.read_bytes()
                info['sha256'] = digest(content)
            current[rel.as_posix()] = info
            dest = mirror / rel
            if old.get(rel.as_posix()) != info or not dest.is_file():
                dest.parent.mkdir(parents=True, exist_ok=True)
                if content is None:
                    shutil.copy2(src, dest)
                else:
                    dest.write_bytes(content)
                    shutil.copystat(src, dest)
                copied += 1
    # Remove only paths previously copied into this private cache, never sources.
    for rel in old.keys() - current.keys():
        target = mirror / rel
        if not target.resolve().is_relative_to(mirror.resolve()):
            raise RuntimeError('Invalid cached source manifest path')
        target.unlink(missing_ok=True)
    json_write(manifest_file, current)
    return copied, len(current)


def map_paths(data, mirror, source, build, preview):
    return data.replace(os.fsencode(mirror), os.fsencode(source)).replace(
        os.fsencode(build), os.fsencode(preview))


def rewrite_synctex(data, mirror, source, build, preview):
    lines = gzip.decompress(data).splitlines(keepends=True)
    result = []
    position = previous_anchor = 0
    for line in lines:
        if line.startswith(b'Input:'):
            prefix, number, filename = line.rstrip(b'\n').split(b':', 2)
            file_path = Path(os.fsdecode(filename))
            if not file_path.is_absolute():
                file_path = mirror / file_path
            filename = map_paths(os.fsencode(file_path), mirror, source, build, preview)
            line = prefix + b':' + number + b':' + filename + b'\n'
        elif line.startswith(b'!') and line[1:].strip().isdigit():
            # Each anchor stores the distance from the previous anchor's start.
            line = b'!' + str(position - previous_anchor).encode() + b'\n'
            previous_anchor = position
        result.append(line)
        position += len(line)
    return gzip.compress(b''.join(result), mtime=0)


def file_state(path):
    """Distinguish current diagnostics from a previous failed build's log."""
    if not path.is_file():
        return None
    stat = path.stat()
    return (stat.st_mtime_ns, stat.st_size, digest(path.read_bytes()))


def diagnostic(path, before, returncode, required=True):
    if not required:
        return {'path': str(path), 'status': 'not_applicable'}
    state = file_state(path)
    status = 'collected' if state and (returncode == 0 or state != before) else 'missing'
    if state and status == 'missing':
        status = 'stale'
    return {'path': str(path), 'status': status, 'sha256': state[2] if state else None}


def run(args):
    started = time.perf_counter()
    if Path(__file__).with_name('.deployment-in-progress.json').exists():
        raise RuntimeError('A deployment is in progress; retry after it completes')
    workspace = Path(getattr(args, 'workspace', WORKSPACE)).resolve(strict=True)
    cache = Path(getattr(args, 'cache_root', CACHE)).resolve()
    document = Path(args.document).resolve(strict=True)
    if not document.is_relative_to(workspace) or document.suffix.lower() != '.tex':
        raise ValueError(f'The root .tex file must be inside {workspace}')
    document_dir = document.parent
    source = document_dir
    papers = workspace / 'papers'
    if document.is_relative_to(papers) and len(document.relative_to(papers).parts) > 1:
        source = papers / document.relative_to(papers).parts[0]
    expected_preview = cache / 'preview' / document_dir.relative_to('/')
    preview = Path(args.outdir).resolve() if args.outdir else expected_preview
    if preview != expected_preview:
        raise ValueError(f'Unexpected preview path: use {expected_preview}')
    project = cache / 'projects' / digest(os.fsencode(document_dir))[:24]
    mirror = project / 'source'
    build = project / ('build-' + args.engine) / document.stem / document.stem
    for directory in (project, mirror, build, preview):
        directory.mkdir(parents=True, exist_ok=True)
    with (project / 'build.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if Path(__file__).with_name('.deployment-in-progress.json').exists():
            raise RuntimeError('A deployment is in progress; retry after it completes')
        if getattr(args, 'fresh', False) and build.exists():
            backup = project / 'audit-backups'
            backup.mkdir(exist_ok=True)
            build.rename(backup / f'{args.engine}-{document.stem}-{time.time_ns()}')
            build.mkdir(parents=True)
        sync_start = time.perf_counter()
        copied, total = mirror_project(source, mirror, project / 'source-manifest.json')
        sync_seconds = time.perf_counter() - sync_start
        print(f'[fast-latex] Source sync: {copied}/{total} files copied ({sync_seconds:.2f}s)', flush=True)
        # Overleaf paths are relative to the project root, with local resources
        # also searchable next to a nested main document.
        for directory, dirs, files in os.walk(mirror):
            (build / Path(directory).relative_to(mirror)).mkdir(parents=True, exist_ok=True)
        environment = os.environ.copy()
        modern = Path('/opt/texlive-modern/bin/x86_64-linux')
        if r'\DocumentMetadata{' in document.read_text(errors='replace'):
            if not (modern / 'lualatex').is_file():
                raise RuntimeError('This tagged PDF document needs the modern TeX Live toolchain')
            environment['PATH'] = str(modern) + ':' + environment.get('PATH', '')
        local_dir = mirror / document_dir.relative_to(source)
        for variable in ('TEXINPUTS', 'BIBINPUTS', 'BSTINPUTS'):
            environment[variable] = str(local_dir) + ':' + str(mirror) + '//:' + environment.get(variable, '')
        flag = {'pdf': '-pdf', 'xe': '-xelatex', 'lua': '-lualatex'}[args.engine]
        command = ['latexmk', flag, '-synctex=1', '-interaction=nonstopmode',
                   '-file-line-error', '-halt-on-error', '-outdir=' + str(build),
                   str(mirror / document.relative_to(source))]
        tex_log = build / (document.stem + '.log')
        bib_log = build / (document.stem + '.blg')
        before_logs = {path: file_state(path) for path in (tex_log, bib_log)}
        compile_start = time.perf_counter()
        process = subprocess.Popen(command, cwd=mirror, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True, env=environment)
        def stop_build(signum, frame):
            raise KeyboardInterrupt
        previous_term = signal.signal(signal.SIGTERM, stop_build)
        try:
            with (project / 'last-build.log').open('wb') as logfile:
                for line in process.stdout:
                    logfile.write(line)
                    sys.stdout.buffer.write(map_paths(line, mirror, source, build, preview))
                    sys.stdout.buffer.flush()
            returncode = process.wait()
        except BaseException:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            raise
        finally:
            signal.signal(signal.SIGTERM, previous_term)
        compile_seconds = time.perf_counter() - compile_start
        stem = document.stem
        aux = build / (stem + '.aux')
        aux_data = aux.read_bytes() if aux.exists() else b''
        bibliography_required = b'\\bibdata' in aux_data or b'\\abx@aux@' in aux_data
        result = {
            'schema_version': 1, 'run_id': uuid.uuid4().hex,
            'source': str(document), 'engine': args.engine,
            'returncode': returncode, 'status': 'failed' if returncode else 'succeeded',
            'paths': {'build_dir': str(build), 'stdout_log': str(project / 'last-build.log'),
                      'preview_pdf': str(preview / (stem + '.pdf')),
                      'local_pdf': str(document_dir / 'output' / (stem + '.pdf'))},
            'diagnostics': {
                'tex_log': diagnostic(tex_log, before_logs[tex_log], returncode),
                'bibliography_log': diagnostic(bib_log, before_logs[bib_log], returncode,
                                               bibliography_required)},
            'pdf_published': False,
        }
        def record_result():
            json_write(project / ('last-result-' + args.engine + '-' + stem + '.json'), result)
            if getattr(args, 'result_file', None):
                json_write(Path(args.result_file), result)
        # Publish diagnostics even after a failure, but preserve the last good PDF.
        for suffix in ('.log', '.fls'):
            path = build / (stem + suffix)
            if path.is_file():
                atomic_write(preview / path.name,
                             map_paths(path.read_bytes(), mirror, source, build, preview))
        if returncode:
            record_result()
            print('[fast-latex] Build failed; last successful PDFs have been preserved.', flush=True)
            return returncode
        pdf = build / (stem + '.pdf')
        if not pdf.is_file():
            result.update(returncode=1, status='failed', error='Expected PDF is missing')
            record_result()
            raise RuntimeError('latexmk did not produce the expected PDF')
        publish_start = time.perf_counter()
        synctex = build / (stem + '.synctex.gz')
        if synctex.is_file():
            atomic_write(preview / synctex.name,
                         rewrite_synctex(synctex.read_bytes(), mirror, source, build, preview))
        for suffix in ('.bbl', '.blg'):
            path = build / (stem + suffix)
            if path.is_file():
                atomic_write(preview / path.name, path.read_bytes())
        atomic_write(preview / pdf.name, pdf.read_bytes())
        print(f'[fast-latex] Native preview ready: {preview / pdf.name}', flush=True)
        preview_seconds = time.perf_counter() - publish_start
        copy_start = time.perf_counter()
        destination = document_dir / 'output'
        for suffix in ('.synctex.gz', '.bbl', '.log', '.pdf'):
            path = preview / (stem + suffix)
            if path.is_file():
                atomic_write(destination / path.name, path.read_bytes())
        copy_seconds = time.perf_counter() - copy_start
        timings = {'source': str(document), 'preview_pdf': str(preview / pdf.name),
                   'local_pdf': str(destination / pdf.name), 'engine': args.engine,
                   'copied_files': copied, 'source_files': total,
                   'sync_seconds': round(sync_seconds, 3),
                   'compile_seconds': round(compile_seconds, 3),
                   'publish_seconds': round(preview_seconds, 3),
                   'copy_back_seconds': round(copy_seconds, 3),
                   'total_seconds': round(time.perf_counter() - started, 3)}
        json_write(project / 'last-success.json', timings)
        result.update(pdf_published=True, timings=timings)
        record_result()
        print(f'[fast-latex] PDF synchronized to {destination / pdf.name}', flush=True)
        print('[fast-latex] ' + json.dumps(timings, ensure_ascii=False), flush=True)
        return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', choices=['pdf', 'xe', 'lua'], required=True)
    parser.add_argument('--document', required=True)
    parser.add_argument('--outdir', help='Optional explicit preview path; validated against the cache layout')
    parser.add_argument('--workspace', default=str(WORKSPACE))
    parser.add_argument('--cache-root', default=str(CACHE))
    parser.add_argument('--result-file', help='Write the schema-versioned build result, including actual diagnostic paths')
    parser.add_argument('--fresh', action='store_true', help='Archive this entry cache while holding its build lock')
    args = parser.parse_args()
    try:
        sys.exit(run(args))
    except Exception as exc:
        if args.result_file:
            json_write(Path(args.result_file), {'schema_version': 1, 'source': str(Path(args.document).resolve()),
                       'engine': args.engine, 'status': 'failed', 'returncode': 1,
                       'pdf_published': False, 'error': str(exc), 'diagnostics': {}})
        print(f'[fast-latex] ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
