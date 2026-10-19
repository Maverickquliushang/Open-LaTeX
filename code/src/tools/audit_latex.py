#!/usr/bin/env python3
"""Audit LaTeX using fast_build's result contract. Missing logs mean unknown."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT = Path('/work/papers')
FAST = Path(__file__).with_name('fast_build.py')
SKIP_DIRS = {'output', '.tmp', '.cache', '.git', '.latex-tools', '__pycache__'}


def inventory(root=ROOT):
    rows = []
    for folder in sorted(root.iterdir()):
        if not folder.is_dir() or folder.name in SKIP_DIRS:
            continue
        for doc in sorted(folder.rglob('*.tex')):
            if set(doc.relative_to(folder).parts) & SKIP_DIRS:
                continue
            active = re.sub(r'(?m)(?<!\\)%.*$', '', doc.read_text(errors='replace'))
            if not re.search(r'^\s*\\documentclass', active, re.M):
                continue
            engine = 'pdf'
            if 'lualatex' in doc.name or '\\babelfont' in active or 'DocumentMetadata' in active:
                engine = 'lua'
            elif 'xelatex' in doc.name or re.search(r'\\usepackage(?:\[[^]]*\])?\{(?:fontspec|xeCJK)', active):
                engine = 'xe'
            rows.append(dict(id=len(rows) + 1, folder=folder.name,
                             file=str(doc.relative_to(folder)), source=str(doc), engine=engine,
                             category='sample' if doc.name.startswith('sample-') else 'document'))
    return rows


def read_diagnostic(result, name):
    entry = result.get('diagnostics', {}).get(name, {})
    status, path = entry.get('status', 'not_collected'), entry.get('path')
    if status != 'collected':
        return {'status': status, 'path': path}, None
    if not path:
        return {'status': 'path_error', 'path': None}, None
    try:
        raw = Path(path).read_bytes()
    except OSError as exc:
        return {'status': 'path_error', 'path': path, 'error': str(exc)}, None
    if entry.get('sha256') and hashlib.sha256(raw).hexdigest() != entry['sha256']:
        return {'status': 'changed_after_build', 'path': path}, None
    content = raw.decode(errors='replace')
    if not content.strip():
        return {'status': 'empty', 'path': path}, None
    return {'status': 'collected', 'path': path}, content


def analyze_diagnostics(result, returncode):
    tex_state, texlog = read_diagnostic(result, 'tex_log')
    bib_state, biblog = read_diagnostic(result, 'bibliography_log')
    warnings = citations = fonts = other = None
    overfull = underfull = missing_characters = errors = None
    if texlog is not None:
        warnings = re.findall(
            r'(?:LaTeX(?: Font)?|Package [\w-]+|Class [\w-]+) Warning:[^\n]*'
            r'(?:\n\([^\n]*\)[^\n]*)*', texlog)
        citations = [warning for warning in warnings if re.search(
            r'citation|reference|author undefined|label .*multiply.defined', warning, re.I)]
        missing_characters = re.findall(r'Missing character:[^\n]*', texlog)
        fonts = [warning for warning in warnings if re.search(
            r'font|glyph|character', warning, re.I)] + missing_characters
        other = [warning for warning in warnings if warning not in citations and warning not in fonts]
        overfull = len(re.findall(r'Overfull \\[hv]box', texlog))
        underfull = len(re.findall(r'Underfull \\[hv]box', texlog))
        errors = [line for line in texlog.splitlines() if re.search(
            r'^!|(?:LaTeX|Package [\w-]+) Error:|Undefined control sequence|Emergency stop', line)]
    bibwarnings = None
    if biblog is not None:
        bibwarnings = [line for line in biblog.splitlines() if re.search(
            r'Warning--|\bWARN\b|\bERROR\b|I couldn.t open|I found no|Repeated entry|error message', line)]
    elif bib_state['status'] == 'not_applicable':
        bibwarnings = []
    collected = tex_state['status'] == 'collected' and bib_state['status'] in {'collected', 'not_applicable'}
    issue_count = (len(warnings or []) + len(missing_characters or []) + len(bibwarnings or []) +
                   (overfull or 0) + (underfull or 0) + len(errors or []))
    quality = 'unknown' if not collected else ('issues' if issue_count or returncode else 'passed')
    return {'quality_status': quality,
            'diagnostics': {'tex_log': tex_state, 'bibliography_log': bib_state},
            'warnings': warnings, 'bib_warnings': bibwarnings,
            'citation_reference_issues': citations, 'font_issues': fonts,
            'other_warnings': other, 'overfull': overfull, 'underfull': underfull,
            'missing_characters': missing_characters, 'errors': errors}


def run(row, report, phase, fresh=False, workspace=Path('/work'),
        cache_root=Path('/opt/latex-build/.cache'), fast=FAST, timeout=180):
    doc = Path(row['source'])
    token = f'{row["id"]:02d}-{phase}-{uuid.uuid4().hex[:10]}'
    result_path = report / (token + '.build.json')
    cmd = ['python3', str(fast), '--engine', row['engine'], '--document', str(doc),
           '--workspace', str(workspace), '--cache-root', str(cache_root),
           '--result-file', str(result_path)]
    if fresh:
        cmd.append('--fresh')
    start = time.perf_counter()
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        raw, _ = process.communicate(timeout=timeout)
        code = process.returncode
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            raw, _ = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            raw, _ = process.communicate()
        raw += b'\nAUDIT TIMEOUT\n'
        code = 124
    output = raw.decode(errors='replace')
    wall = time.perf_counter() - start
    logname = token + '.txt'
    (report / logname).write_text(output, encoding='utf-8')
    result, result_error = {}, None
    try:
        result = json.loads(result_path.read_text(encoding='utf-8'))
        if (not isinstance(result, dict) or result.get('schema_version') != 1 or result.get('source') != str(doc.resolve())
                or result.get('engine') != row['engine'] or result.get('returncode') != code):
            raise ValueError('Build result identity or return code mismatch')
    except (OSError, ValueError, TypeError) as exc:
        result_error, result = str(exc), {}
    analysis = analyze_diagnostics(result, code)
    pdfpath = result.get('paths', {}).get('preview_pdf')
    pdf = Path(pdfpath) if pdfpath else None
    pages = pdf_bytes = None
    if code == 0 and result.get('pdf_published') and pdf and pdf.is_file():
        info = subprocess.run(['pdfinfo', str(pdf)], capture_output=True, text=True)
        match = re.search(r'^Pages:\s+(\d+)', info.stdout, re.M)
        pages = int(match[1]) if info.returncode == 0 and match else None
        pdf_bytes = pdf.stat().st_size
    if code == 0 and (not result.get('pdf_published') or pdf_bytes is None or pages is None):
        analysis['quality_status'] = 'unknown'
    item = dict(**row, phase=phase, returncode=code,
                compilation_status='succeeded' if code == 0 else 'failed',
                wall_seconds=round(wall, 3), timings=result.get('timings'),
                pages=pages, pdf_bytes=pdf_bytes, log=logname,
                build_result=str(result_path), result_error=result_error, **analysis)
    with (report / 'runs.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(item, ensure_ascii=False) + '\n')
    print(json.dumps({key: item[key] for key in
          ['id', 'file', 'phase', 'returncode', 'quality_status', 'wall_seconds', 'pages']},
          ensure_ascii=False), flush=True)
    return item


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True)
    parser.add_argument('--ids', default='')
    parser.add_argument('--phase', default='initial')
    parser.add_argument('--fresh', action='store_true')
    parser.add_argument('--root', type=Path, help='Paper collection; defaults to WORKSPACE/papers')
    parser.add_argument('--workspace', type=Path, default=Path('/work'))
    parser.add_argument('--cache-root', type=Path, default=Path('/opt/latex-build/.cache'))
    parser.add_argument('--fast', type=Path, default=FAST)
    parser.add_argument('--timeout', type=float, default=180)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.phase):
        parser.error('--phase must contain only letters, digits, underscores, and hyphens')
    report = Path(args.report).resolve()
    report.mkdir(parents=True, exist_ok=True)
    rows = inventory((args.root or args.workspace / 'papers').resolve())
    (report / 'inventory.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    ids = {int(value) for value in args.ids.split(',') if value}
    items = []
    for row in rows:
        if not ids or row['id'] in ids:
            items.append(run(row, report, args.phase, args.fresh, args.workspace,
                             args.cache_root, args.fast, args.timeout))
    summary = {'entries': len(items),
               'compilation_failed': sum(item['returncode'] != 0 for item in items),
               'quality': {state: sum(item['quality_status'] == state for item in items)
                           for state in ('passed', 'issues', 'unknown')}}
    summary['status'] = ('unknown' if not items or summary['quality']['unknown'] else
                         'issues' if summary['compilation_failed'] or summary['quality']['issues'] else 'passed')
    (report / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary), flush=True)
    sys.exit({'passed': 0, 'issues': 1, 'unknown': 2}[summary['status']])
