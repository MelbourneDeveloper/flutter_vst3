#!/usr/bin/env python3
"""Check per-package line coverage against the floors in coverage-thresholds.json.

Only files under a package's lib/ count. Files the test run never loaded are
counted at 0% using their non-blank, non-comment source lines. Duplicate lcov
records for the same file or line are merged.
"""
import json
import pathlib
import sys
from dataclasses import dataclass

REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
THRESHOLDS_FILE = 'coverage-thresholds.json'
LCOV_FILE = 'coverage/lcov.info'
COMMENT_STARTS = ('//', '/*', '*')


@dataclass
class Stats:
    package: str
    lines: int
    hit: int
    percent: float
    floor: float
    unloaded: list

    @property
    def below(self):
        return self.percent < self.floor


def load_thresholds(repo):
    path = repo / THRESHOLDS_FILE
    if not path.is_file():
        raise SystemExit(f'error: missing thresholds file {path}')
    return json.loads(path.read_text(encoding='utf-8'))['packages']


def lcov_packages(root):
    """Package names (relative to root) that have a coverage/lcov.info file."""
    return {path.parent.parent.relative_to(root).as_posix(): path
            for path in root.rglob(LCOV_FILE)}


def lib_relative(source, package_dir):
    """Return a lib-relative path, or None when the source is outside lib/."""
    lib = (package_dir / 'lib').resolve()
    raw = pathlib.Path(source.strip().replace('\\', '/'))
    for candidate in (raw, package_dir / raw):
        resolved = candidate.resolve()
        if resolved == lib or lib in resolved.parents:
            return resolved.relative_to(lib).as_posix()
    return None


def parse_records(path, package_dir):
    """Map lib-relative file name to {line: hit}, merging duplicate records."""
    records = {}
    current = None
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if line.startswith('SF:'):
            current = lib_relative(line[3:], package_dir)
        elif line.startswith('DA:') and current is not None:
            number, count = (int(field) for field in line[3:].split(',')[:2])
            lines = records.setdefault(current, {})
            lines[number] = lines.get(number, False) or count > 0
    return records


def code_lines(path):
    """Count non-blank, non-comment source lines."""
    return sum(1 for line in path.read_text(encoding='utf-8', errors='replace').splitlines()
               if line.strip() and not line.strip().startswith(COMMENT_STARTS))


def package_stats(root, package, floor):
    package_dir = root / package
    lcov = package_dir / LCOV_FILE
    if not lcov.is_file():
        raise CheckError(f'{package}: missing {lcov}')
    records = parse_records(lcov, package_dir)
    recorded = sum(len(lines) for lines in records.values())
    if recorded == 0:
        raise CheckError(f'{package}: empty lcov {lcov}')
    hit = sum(sum(lines.values()) for lines in records.values())
    sources = {path.relative_to(package_dir / 'lib').as_posix(): path
               for path in (package_dir / 'lib').rglob('*.dart') if path.is_file()}
    unloaded = [(name, code_lines(path)) for name, path in sorted(sources.items())
                if name not in records]
    lines = recorded + sum(count for _, count in unloaded)
    percent = 100.0 * hit / lines if lines else 0.0
    return Stats(package, lines, hit, percent, floor, unloaded)


class CheckError(Exception):
    """A structural coverage problem that must fail the check."""


def validate(root, thresholds):
    """Return the packages to check, raising CheckError on bad trees."""
    packages = lcov_packages(root)
    unknown = [name for name in thresholds if not (root / name / 'lib').is_dir()]
    if unknown:
        raise CheckError(f'unknown package(s) in {THRESHOLDS_FILE}: {", ".join(sorted(unknown))}')
    unlisted = sorted(set(packages) - set(thresholds))
    if unlisted:
        raise CheckError(f'package(s) with no thresholds entry: {", ".join(unlisted)}')
    return sorted(thresholds)


def print_stats(stats):
    print(stats.package)
    for name, count in stats.unloaded:
        print(f'  MISSING lib/{name}: {count} lines, 0.0%')
    print('  lines  hit  percent  floor  status')
    status = 'BELOW' if stats.below else 'ok'
    print(f'  {stats.lines:5d}  {stats.hit:3d}  {stats.percent:6.1f}%'
          f'  {stats.floor:5.1f}  {status}')


def report(results):
    for stats in results:
        print_stats(stats)
    failures = [stats for stats in results if stats.below]
    for stats in failures:
        print(f'error: {stats.package} {stats.percent:.1f}% is below floor {stats.floor:.1f}%',
              file=sys.stderr)
    return 1 if failures else 0


def main(argv):
    root = pathlib.Path(argv[1]).resolve() if len(argv) > 1 else REPO_ROOT
    thresholds = load_thresholds(root)
    try:
        packages = validate(root, thresholds)
        results = [package_stats(root, package, float(thresholds[package]))
                   for package in packages]
    except CheckError as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return report(results)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
