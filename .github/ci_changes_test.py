#!/usr/bin/env python3
"""Drives ci_changes.py on real git history, and checks ci.yml uses its answer."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / '.github/ci_changes.py'
PUBSPEC = 'name: a\nversion: 1.0.0\ndependencies:\n  ffi: ^2.1.0\n'
LOCK = ('packages:\n  ffi:\n    source: hosted\n    version: "2.1.0"\n'
        '  flutter_vst3:\n    source: path\n    version: "0.1.2"\n')
BASE = {'lib/a.dart': 'code\n', 'README.md': 'old\n', 'pkg/README.md': 'old\n', 'pubspec.yaml': PUBSPEC, 'pubspec.lock': LOCK,
        'Makefile': 'all:\n', 'docs/a.txt': 'old\n'}


def run_git(repo, *args):
    subprocess.run(('git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', *args),
                   check=True, capture_output=True)


def write(repo, files):
    for name, content in files.items():
        path = pathlib.Path(repo, name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def classify(files, deleted=()):
    with tempfile.TemporaryDirectory() as repo:
        run_git(repo, 'init', '-q')
        write(repo, BASE)
        run_git(repo, 'add', '-A')
        run_git(repo, 'commit', '-qm', 'base')
        write(repo, files)
        for name in deleted:
            pathlib.Path(repo, name).unlink()
        run_git(repo, 'add', '-A')
        run_git(repo, 'commit', '-qm', 'change', '--allow-empty')
        result = subprocess.run((sys.executable, SCRIPT, 'HEAD^1', 'HEAD'), cwd=repo, check=True,
                                capture_output=True, text=True)
        return result.stdout.strip()


class Classifier(unittest.TestCase):
    def test_unbuilt_changes_skip(self):
        for files in ({}, {'pkg/README.md': 'new\n'}, {'docs/a.txt': 'new\n'}, {'Makefile': 'other:\n'},
                      {'.gitignore': 'x\n'}, {'.claude/settings.json': '{}\n'},
                      {'.github/workflows/ci.yml': 'x\n'}, {'pkg/CHANGELOG.md': 'x\n'},
                      {'pubspec.yaml': PUBSPEC.replace('1.0.0', '2.0.0')},
                      {'pubspec.lock': LOCK.replace('0.1.2', '0.2.0')}):
            self.assertEqual(classify(files), 'false', files)
        self.assertEqual(classify({}, deleted=['pkg/README.md']), 'false')

    def test_built_changes_run(self):
        for files in ({'README.md': 'new\n'}, {'lib/a.dart': 'new\n'}, {'lib/new.dart': 'new\n'}, {'a.md.dart': 'x\n'},
                      {'pkg/Makefile': 'x\n'}, {'native/a.cpp': 'x\n'}, {'.github/actions/a.yml': 'x\n'},
                      {'pubspec.yaml': PUBSPEC.replace('^2.1.0', '^2.2.0')},
                      {'pubspec.yaml': PUBSPEC.replace('1.0.0', '2.0.0') + 'x: y\n'},
                      {'pubspec.lock': LOCK.replace('"2.1.0"', '"2.2.0"')},
                      {'pkg/pubspec.yaml': PUBSPEC},
                      {'pkg/README.md': 'new\n', 'lib/a.dart': 'new\n'}):
            self.assertEqual(classify(files), 'true', files)
        self.assertEqual(classify({}, deleted=['lib/a.dart']), 'true')
        self.assertEqual(classify({}, deleted=['pubspec.yaml']), 'true')


class Workflow(unittest.TestCase):
    def setUp(self):
        self.ci = (ROOT / '.github/workflows/ci.yml').read_text()

    def job(self, name):
        return re.search(rf'(?ms)^  {name}:\n.*?(?=^  [a-z-]+:\n|\Z)', self.ci).group(0)

    def test_only_a_pull_request_can_skip(self):
        self.assertIn('github.event_name }}" = pull_request', self.job('changes'))
        self.assertIn('ci_changes.py HEAD^1 HEAD', self.job('changes'))
        self.assertIn('code=true', self.job('changes'))

    def test_build_is_gated_and_the_root_job_rejects_a_wrong_skip(self):
        self.assertIn("if: needs.changes.outputs.code == 'true'", self.job('build'))
        root = self.job('ci')
        self.assertIn('- changes', root)
        self.assertIn("contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')", root)
        self.assertIn("contains(needs.*.result, 'skipped') && needs.changes.outputs.code != 'false'", root)

    def test_gates_always_run(self):
        self.assertNotIn('if:', self.job('analyze').split('steps:')[0])
        self.assertIn('!cancelled()', self.job('repository-rules'))
        self.assertIn('ci_changes_test.py', self.job('repository-rules'))

    def test_steps_that_need_binaries_run_only_with_a_build(self):
        rules = self.job('repository-rules')
        for step in ('restore-build', 'docs_commands_test.py'):
            self.assertRegex(rules, re.escape(step) + r"\n\s+if: needs\.changes\.outputs\.code == 'true'")


if __name__ == '__main__':
    unittest.main()
