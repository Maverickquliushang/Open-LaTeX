#!/usr/bin/env python3
"""Run real LaTeX regressions in an isolated Linux container.

python3 /repo/tests/test_build_audit.py --work-root /work --report /work/regressions.json
All fixtures are original; no personal manuscript or existing container is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src' / 'tools'))
import audit_latex

WORK_ROOT = Path('/work')
RUN_ROOT = None
RUNS = []


def document(body, packages=''):
    return '\\documentclass{article}\n' + packages + '\n\\begin{document}\n' + body + '\n\\end{document}\n'


class BuildAuditTests(unittest.TestCase):
    def setUp(self):
        self.workspace = RUN_ROOT / self._testMethodName
        self.folder = self.workspace / 'papers' / 'original-fixture'
        self.folder.mkdir(parents=True)
        self.report = self.workspace / 'reports'
        self.report.mkdir()

    def write(self, relative, content):
        path = self.folder / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')
        return path

    def build(self, relative='main.tex', fresh=False):
        source = self.folder / relative
        row = dict(id=len(RUNS) + 1, folder=self.folder.name, file=relative,
                   source=str(source), engine='pdf', category='test')
        result = audit_latex.run(row, self.report, 'regression', fresh,
                                 self.workspace, self.workspace / '.cache')
        RUNS.append(result)
        return result

    def build_result(self, item):
        return json.loads(Path(item['build_result']).read_text())

    def cli_audit(self, expected_code):
        report = self.workspace / 'cli-report'
        process = subprocess.run([sys.executable, str(audit_latex.FAST.with_name('audit_latex.py')),
                                  '--workspace', str(self.workspace), '--cache-root', str(self.workspace / '.cache'),
                                  '--report', str(report)], capture_output=True, text=True)
        self.assertEqual(process.returncode, expected_code, process.stdout + process.stderr)
        return json.loads((report / 'summary.json').read_text())

    def test_clean_document_and_cached_build(self):
        self.write('main.tex', document('An original clean document.'))
        first = self.build()
        self.assertEqual(first['returncode'], 0)
        self.assertEqual(first['quality_status'], 'passed')
        self.assertEqual(first['warnings'], [])
        self.assertEqual(first['pages'], 1)
        again = self.build()
        self.assertEqual(again['quality_status'], 'passed')
        self.assertEqual(again['timings']['copied_files'], 0)
        result = self.build_result(again)
        self.assertTrue(Path(result['diagnostics']['tex_log']['path']).is_file())
        self.assertEqual(self.cli_audit(0)['status'], 'passed')

    def test_empty_inventory_is_unknown(self):
        summary = self.cli_audit(2)
        self.assertEqual(summary['status'], 'unknown')
        self.assertEqual(summary['entries'], 0)

    def test_missing_reference_and_fixed_bibliography(self):
        self.write('main.tex', document('See \\cite{original-book}.'))
        missing = self.build()
        self.assertEqual(missing['returncode'], 0)
        self.assertEqual(missing['quality_status'], 'issues')
        self.assertTrue(missing['citation_reference_issues'])
        self.write('refs.bib', '@book{original-book,author={Avery Example},title={An Original Test},year={2026},publisher={Test Press}}\n')
        self.write('main.tex', document('See \\cite{original-book}.\n\\bibliographystyle{plain}\n\\bibliography{refs}'))
        fixed = self.build()
        self.assertEqual(fixed['quality_status'], 'passed')
        self.assertEqual(fixed['citation_reference_issues'], [])
        self.assertEqual(fixed['diagnostics']['bibliography_log']['status'], 'collected')

    def test_natbib_author_warning_and_minimal_fix(self):
        self.write('refs.bib', '@book{original-book,author={Avery Example},title={An Original Test},year={2026},publisher={Test Press}}\n')
        ending = '\n\\bibliographystyle{unsrt}\n\\bibliography{refs}'
        self.write('main.tex', document('As \\citet{original-book} explains.' + ending,
                                        '\\usepackage[numbers]{natbib}'))
        warning = self.build()
        self.assertEqual(warning['returncode'], 0)
        self.assertTrue(any('Author undefined' in entry for entry in warning['citation_reference_issues']))
        self.write('main.tex', document('As Avery Example \\citep{original-book} explains.' + ending,
                                        '\\usepackage[numbers]{natbib}'))
        fixed = self.build()
        self.assertEqual(fixed['quality_status'], 'passed')

    def test_bibtex_warning_is_separate_from_return_code(self):
        self.write('refs.bib', '@book{original-book,title={An Original Test},year={2026},publisher={Test Press}}\n')
        self.write('main.tex', document('See \\cite{original-book}.\n\\bibliographystyle{plain}\n\\bibliography{refs}'))
        warning = self.build()
        self.assertEqual(warning['returncode'], 0)
        self.assertEqual(warning['quality_status'], 'issues')
        self.assertTrue(warning['bib_warnings'])
        self.assertEqual(warning['font_issues'], [])
        self.write('main.tex', document('This entry no longer uses a bibliography.'))
        removed = self.build()
        self.assertEqual(removed['diagnostics']['bibliography_log']['status'], 'not_applicable')
        self.assertEqual(removed['bib_warnings'], [])
        self.assertEqual(removed['quality_status'], 'passed')

    def test_missing_stale_and_empty_logs_are_unknown(self):
        self.write('main.tex', document('An original clean document.'))
        item = self.build()
        result = self.build_result(item)
        tex = result['diagnostics']['tex_log']
        current_log = Path(tex['path'])
        current_log.write_bytes(current_log.read_bytes() + b'\nChanged after the build result.\n')
        changed = audit_latex.analyze_diagnostics(result, 0)
        self.assertEqual(changed['quality_status'], 'unknown')
        self.assertEqual(changed['diagnostics']['tex_log']['status'], 'changed_after_build')
        tex['path'] = str(self.workspace / 'does-not-exist.log')
        absent = audit_latex.analyze_diagnostics(result, 0)
        self.assertEqual(absent['quality_status'], 'unknown')
        self.assertIsNone(absent['warnings'])
        self.assertIsNone(absent['overfull'])
        self.assertEqual(absent['diagnostics']['tex_log']['status'], 'path_error')
        tex['status'] = 'stale'
        self.assertEqual(audit_latex.analyze_diagnostics(result, 1)['quality_status'], 'unknown')
        tex['status'] = 'collected'
        tex.pop('sha256', None)
        empty = self.workspace / 'empty.log'
        empty.touch()
        tex['path'] = str(empty)
        self.assertEqual(audit_latex.analyze_diagnostics(result, 0)['diagnostics']['tex_log']['status'], 'empty')
        self.assertEqual(audit_latex.analyze_diagnostics({}, 0)['quality_status'], 'unknown')

    def test_nested_main_and_independent_entry_caches(self):
        self.write('shared.tex', 'Original shared content.\n')
        self.write('nested/main.tex', document('\\input{shared}'))
        self.write('nested/second.tex', document('Second original entry.'))
        self.write('other/main.tex', document('Another main in a different directory.'))
        rows = [self.build(relative) for relative in ('nested/main.tex', 'nested/second.tex', 'other/main.tex')]
        for item in rows:
            self.assertEqual(item['quality_status'], 'passed')
        paths = [self.build_result(item)['paths']['build_dir'] for item in rows]
        self.assertEqual(len(set(paths)), 3)
        logs = [self.build_result(item)['diagnostics']['tex_log']['path'] for item in rows]
        self.assertEqual(len(set(logs)), 3)
        fresh = self.build('nested/main.tex', fresh=True)
        self.assertEqual(fresh['quality_status'], 'passed')
        self.assertTrue(Path(paths[1]).is_dir(), 'Fresh build must preserve the other entry cache')
        self.assertEqual(self.build('nested/second.tex')['quality_status'], 'passed')

    def test_failure_preserves_both_published_pdfs(self):
        self.write('main.tex', document('Original successful output.'))
        initial = self.build()
        paths = self.build_result(initial)['paths']
        pdfs = [Path(paths[key]) for key in ('preview_pdf', 'local_pdf')]
        before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in pdfs]
        self.write('main.tex', document('\\UndefinedCommandForRegression'))
        failed = self.build()
        self.assertNotEqual(failed['returncode'], 0)
        self.assertFalse(self.build_result(failed)['pdf_published'])
        self.assertEqual(failed['diagnostics']['tex_log']['status'], 'collected')
        self.assertNotEqual(failed['quality_status'], 'passed')
        self.assertEqual(before, [hashlib.sha256(path.read_bytes()).hexdigest() for path in pdfs])

    def test_font_and_layout_are_separate_categories(self):
        self.write('main.tex', document('\\char255\n\\hbox to 1pt{An intentionally overfull original box.}'))
        item = self.build()
        self.assertEqual(item['returncode'], 0)
        self.assertEqual(item['quality_status'], 'issues')
        self.assertTrue(item['font_issues'])
        self.assertGreater(item['overfull'], 0)
        self.assertEqual(item['citation_reference_issues'], [])
        self.assertEqual(self.cli_audit(1)['status'], 'issues')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-root', type=Path, default=WORK_ROOT)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    RUN_ROOT = args.work_root.resolve() / ('build-audit-' + str(time.time_ns()))
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BuildAuditTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = {'success': result.wasSuccessful(), 'tests': result.testsRun,
               'failures': [(str(test), trace) for test, trace in result.failures],
               'errors': [(str(test), trace) for test, trace in result.errors],
               'artifact_root': str(RUN_ROOT), 'build_runs': RUNS}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    sys.exit(0 if result.wasSuccessful() else 1)
