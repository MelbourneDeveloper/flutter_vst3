"""Exercise public dependency and native-library targets in a clean scratch tree."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
PACKAGES = ('dart_vst_host', 'dart_vst_graph', 'flutter_vst3', 'vsts/echo', 'vsts/flutter_reverb')


def scratch():
    destination = pathlib.Path(tempfile.mkdtemp(prefix='review_c_make_'))
    shutil.copytree(ROOT, destination, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.git', '.dart_tool', 'build', 'ephemeral',
                                                  '.symlinks', '*.so', '*.dylib', '*.dll'))
    return destination


STANDALONE_DART = """#!/usr/bin/env bash
# A dart with no Flutter refuses a package that depends on the Flutter SDK. The
# dart that comes with Flutter doesn't, which would hide the wrong command here.
if [ "$1 $2" = "pub get" ] && grep -q 'sdk: flutter' pubspec.yaml; then
  echo "Because $PWD requires the Flutter SDK, version solving failed." >&2
  exit 65
fi
exec "%s" "$@"
"""


def standalone_dart_path():
    directory = pathlib.Path(tempfile.mkdtemp(prefix='review_c_dart_'))
    shim = directory / 'dart'
    shim.write_text(STANDALONE_DART % shutil.which('dart'))
    shim.chmod(0o755)
    return directory


def invoke(root, target, path_prefix=None):
    env = dict(os.environ)
    if path_prefix:
        env['PATH'] = str(path_prefix) + os.pathsep + env['PATH']
    result = subprocess.run(['make', target], cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, env=env)
    if result.returncode != 0:
        raise AssertionError(result.stdout)
    return result.stdout


class PublicMakeTargets(unittest.TestCase):
    def test_M17_clean_dart_deps_resolves_all_packages(self):
        root = scratch()
        self.addCleanup(shutil.rmtree, root)
        for package in PACKAGES:
            self.assertFalse((root / package / '.dart_tool/package_config.json').exists())
        shim = standalone_dart_path()
        self.addCleanup(shutil.rmtree, shim)
        invoke(root, 'dart-deps', shim)
        for package in PACKAGES:
            self.assertTrue((root / package / '.dart_tool/package_config.json').is_file(), package)

    def test_T2_native_copies_fresh_libraries(self):
        root = scratch()
        self.addCleanup(shutil.rmtree, root)
        start = time.time_ns()
        invoke(root, 'native')
        for package in ('dart_vst_host', 'dart_vst_graph'):
            path = root / package / ('lib' + package + '.so')
            self.assertTrue(path.is_file(), str(path))
            self.assertGreater(path.stat().st_mtime_ns, start, str(path))
            self.assertEqual((root / path.name).read_bytes(), path.read_bytes())


class DeployTargets(unittest.TestCase):
    def deploy(self, root, home, plugin):
        env = dict(os.environ, HOME=str(home))
        return subprocess.run(['make', '-C', 'vsts/' + plugin, '-o', 'build', 'deploy'], cwd=root,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)

    def test_deploy_copies_one_plugin_and_fails_without_touching_a_missing_build(self):
        root = scratch()
        home = pathlib.Path(tempfile.mkdtemp(prefix='review_c_home_'))
        self.addCleanup(shutil.rmtree, root)
        self.addCleanup(shutil.rmtree, home)
        folder = home / ('Library/Audio/Plug-Ins/VST3' if sys.platform == 'darwin' else '.vst3')
        folder.mkdir(parents=True)
        (folder / 'echo.vst3').symlink_to(home / 'gone')
        (folder / 'other.vst3').mkdir()
        bundles = {name: root / 'vsts' / name / 'build/VST3/Release' / (name + '.vst3')
                   for name in ('echo', 'flutter_reverb')}
        for name, bundle in bundles.items():
            bundle.mkdir(parents=True)
            (bundle / 'marker').write_text(name)

        echo = self.deploy(root, home, 'echo')
        self.assertEqual(0, echo.returncode, echo.stdout)
        self.assertFalse((folder / 'echo.vst3').is_symlink())
        self.assertEqual('echo', (folder / 'echo.vst3/marker').read_text())
        self.assertFalse((folder / 'flutter_reverb.vst3').exists())
        self.assertTrue((folder / 'other.vst3').is_dir())

        reverb = self.deploy(root, home, 'flutter_reverb')
        self.assertEqual(0, reverb.returncode, reverb.stdout)
        self.assertEqual('flutter_reverb', (folder / 'flutter_reverb.vst3/marker').read_text())
        self.assertEqual('echo', (folder / 'echo.vst3/marker').read_text())

        shutil.rmtree(bundles['echo'])
        missing = self.deploy(root, home, 'echo')
        self.assertNotEqual(0, missing.returncode, missing.stdout)
        self.assertEqual('echo', (folder / 'echo.vst3/marker').read_text())


if __name__ == '__main__':
    unittest.main()
