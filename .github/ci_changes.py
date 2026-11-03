#!/usr/bin/env python3
"""Prints true when the change between two revisions needs the build and test jobs.

Docs, config and version numbers build nothing. Every other file needs a build,
and so does the root README: docs_commands_test.py runs the commands it documents.
"""
import re
import subprocess
import sys

UNBUILT_PATH = re.compile(
    r'(?<!^README)\.md$|^docs/|^\.claude/|^\.gitignore$|^LICENSE$|^Makefile$'
    r'|^\.github/workflows/ci\.yml$|^\.github/ci_changes(_test)?\.py$')


def git(*args):
    return subprocess.run(('git', *args), check=True, capture_output=True, text=True).stdout


def contents(revision, path):
    listed = git('ls-tree', '--name-only', revision, '--', path).strip()
    return git('show', f'{revision}:{path}') if listed else None


def without_package_version(pubspec):
    return re.sub(r'(?m)^version:.*\n?', '', pubspec, count=1)


def without_path_dependency_versions(lock):
    blocks = re.split(r'(?m)^(?=  \S+:$)', lock)
    return ''.join(re.sub(r'(?m)^    version:.*\n', '', block) if 'source: path' in block else block
                   for block in blocks)


def only_version_changed(path, before, after):
    if before is None or after is None:
        return False
    if path.endswith('pubspec.yaml'):
        return without_package_version(before) == without_package_version(after)
    if path.endswith('pubspec.lock'):
        return without_path_dependency_versions(before) == without_path_dependency_versions(after)
    return False


def needs_build(base, head):
    paths = git('diff', '--name-only', '--no-renames', base, head).splitlines()
    return any(not UNBUILT_PATH.search(path)
               and not only_version_changed(path, contents(base, path), contents(head, path))
               for path in paths)


if __name__ == '__main__':
    print('true' if needs_build(sys.argv[1], sys.argv[2]) else 'false')
