#!/usr/bin/env python3
"""End-to-end tests for coverage_check.py against disposable package trees."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / 'coverage_check.py'
COVERAGE = 'coverage/lcov.info'
THRESHOLDS = 'coverage-thresholds.json'


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


def make_tree(test, packages, floors):
    """Build a temporary repository with a byte-for-byte copy of the checker."""
    root = pathlib.Path(tempfile.mkdtemp(prefix='coverage_check_'))
    test.addCleanup(shutil.rmtree, root)
    checker = root / 'flutter_vst3/test/native/coverage_check.py'
    checker.parent.mkdir(parents=True)
    shutil.copy2(SCRIPT, checker)
    write(root / THRESHOLDS, json.dumps({'_doc': 'test floors', 'packages': floors}))
    for name, spec in packages.items():
        (root / name / 'lib').mkdir(parents=True, exist_ok=True)
        for relative, source in spec.get('sources', {}).items():
            write(root / name / 'lib' / relative, source)
        if spec.get('lcov') is not None:
            write(root / name / COVERAGE, spec['lcov'])
        for relative, source in spec.get('extra', {}).items():
            write(root / name / relative, source)
    return root


def invoke(root, *arguments):
    command = [sys.executable, str(SCRIPT), str(root)]
    return subprocess.run(command + list(arguments), capture_output=True, text=True)


def invoke_default(root):
    script = root / 'flutter_vst3/test/native/coverage_check.py'
    return subprocess.run([sys.executable, str(script)], capture_output=True, text=True)


def output(result):
    return result.stdout + result.stderr


def lcov(*records):
    return ''.join(f'SF:{source}\n{lines}end_of_record\n' for source, lines in records)


ONE_LINE = {'sources': {'a.dart': 'int a = 1;\n'}, 'lcov': lcov(('lib/a.dart', 'DA:1,1\n'))}
TWO_LINES = 'int a = 1;\nint b = 2;\n'


class CoverageCheckTests(unittest.TestCase):
    def check(self, code, package, floors):
        """Runs the checker on one package named pkg and asserts its exit code."""
        result = invoke(make_tree(self, {'pkg': package}, floors))
        self.assertEqual(code, result.returncode, output(result))
        return result

    def test_duplicate_records_merge_and_a_line_hit_anywhere_wins(self):
        result = self.check(0, {
            'sources': {'a.dart': TWO_LINES},
            'lcov': lcov(('lib/a.dart', 'DA:1,0\nDA:2,1\nDA:1,1\n'),
                         ('lib/a.dart', 'DA:1,1\nDA:2,0\n')),
        }, {'pkg': 100.0})
        self.assertIn('2    2   100.0%  100.0  ok', result.stdout)
        self.assertNotIn('BELOW', result.stdout)

    def test_unloaded_file_counts_zero_and_is_listed(self):
        result = self.check(0, {
            'sources': {'a.dart': TWO_LINES, 'b.dart': TWO_LINES},
            'lcov': lcov(('lib/a.dart', 'DA:1,1\nDA:2,1\n')),
        }, {'pkg': 50.0})
        self.assertIn('MISSING lib/b.dart: 2 lines, 0.0%', result.stdout)
        self.assertNotIn('MISSING lib/a.dart', result.stdout)
        self.assertIn('4    2    50.0%   50.0  ok', result.stdout)

    def test_comment_only_and_blank_unloaded_files_add_no_lines(self):
        result = self.check(0, {
            'sources': {**ONE_LINE['sources'],
                        'comments.dart': '// only\n\n/* block\n * more\n */\n',
                        'blank.dart': '\n\n   \n',
                        'mixed.dart': '// lead\nint x = 1; // tail\n/* block\n */\nint y = 2;\n'},
            'lcov': ONE_LINE['lcov'],
        }, {'pkg': 33.3})
        self.assertIn('MISSING lib/comments.dart: 0 lines, 0.0%', result.stdout)
        self.assertIn('MISSING lib/blank.dart: 0 lines, 0.0%', result.stdout)
        self.assertIn('MISSING lib/mixed.dart: 2 lines, 0.0%', result.stdout)
        self.assertIn('3    1    33.3%   33.3  ok', result.stdout)

    def test_below_floor_fails_and_exactly_at_floor_passes(self):
        package = {'sources': {'a.dart': TWO_LINES},
                   'lcov': lcov(('lib/a.dart', 'DA:1,1\nDA:2,0\n'))}
        below = self.check(1, package, {'pkg': 50.1})
        self.assertIn('BELOW', below.stdout)
        self.assertIn('below floor 50.1%', below.stderr)
        self.assertIn('2    1    50.0%   50.0  ok', self.check(0, package, {'pkg': 50.0}).stdout)

    def test_missing_lcov_fails(self):
        root = make_tree(self, {'pkg': {'sources': ONE_LINE['sources']}}, {'pkg': 0.0})
        result = invoke(root)
        self.assertEqual(1, result.returncode, output(result))
        self.assertIn(f'missing {root.resolve() / "pkg" / COVERAGE}', result.stderr)

    def test_empty_lcov_fails(self):
        for contents in ('', '\n  \n', lcov(('lib/a.dart', ''))):
            with self.subTest(contents=contents):
                result = self.check(1, {'sources': ONE_LINE['sources'], 'lcov': contents}, {'pkg': 0.0})
                self.assertIn('empty lcov', result.stderr)

    def test_unknown_package_in_thresholds_fails(self):
        result = self.check(1, ONE_LINE, {'pkg': 100.0, 'ghost': 10.0})
        self.assertIn('unknown package(s)', result.stderr)
        self.assertIn('ghost', result.stderr)

    def test_package_without_thresholds_entry_fails(self):
        result = self.check(1, ONE_LINE, {})
        self.assertIn('no thresholds entry', result.stderr)
        self.assertIn('pkg', result.stderr)

    def test_files_outside_lib_are_ignored(self):
        result = self.check(0, {
            'sources': ONE_LINE['sources'],
            'extra': {'test/a_test.dart': TWO_LINES},
            'lcov': lcov(('lib/a.dart', 'DA:1,1\n'),
                         ('test/a_test.dart', 'DA:1,1\nDA:2,1\n'),
                         ('other/lib/ignored.dart', 'DA:1,1\nDA:2,1\n')),
        }, {'pkg': 100.0})
        self.assertIn('1    1   100.0%  100.0  ok', result.stdout)
        self.assertNotIn('MISSING lib/a.dart', result.stdout)

    def test_absolute_and_relative_paths_merge_one_file(self):
        root = make_tree(self, {'pkg': {'sources': {'a.dart': TWO_LINES}}}, {'pkg': 100.0})
        write(root / 'pkg' / COVERAGE,
              lcov(('lib/a.dart', 'DA:1,1\n'), (str(root / 'pkg/lib/a.dart'), 'DA:2,1\n')))
        result = invoke(root)
        self.assertEqual(0, result.returncode, output(result))
        self.assertIn('2    2   100.0%  100.0  ok', result.stdout)

    def test_default_root_is_the_script_repository(self):
        root = make_tree(self, {'pkg': ONE_LINE}, {'pkg': 100.0})
        result = invoke_default(root)
        self.assertEqual(0, result.returncode, output(result))
        self.assertEqual(result.stdout, invoke(root).stdout)

    def test_missing_thresholds_file_fails(self):
        root = make_tree(self, {}, {})
        (root / THRESHOLDS).unlink()
        result = invoke(root)
        self.assertEqual(1, result.returncode, output(result))
        self.assertIn('missing thresholds file', result.stderr)


if __name__ == '__main__':
    unittest.main()
