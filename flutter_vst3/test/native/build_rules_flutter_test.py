"""Real Linux Echo configure and ELF runpath regressions."""
import pathlib
import re
import shutil
import subprocess
import unittest
from build_rules_make_test import scratch, invoke


def command(root, args):
    return subprocess.run(args, cwd=root, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True)


def configure(root, name):
    return command(root, ['cmake', '-S', 'vsts/echo', '-B', str(root / name),
                          '-DCMAKE_BUILD_TYPE=Release', '-DFLUTTER_VST3_NATIVE_UI_ONLY=OFF'])


class FlutterBuildRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = scratch()
        invoke(cls.root, 'dart-deps')
        result = command(cls.root / 'vsts/echo', ['flutter', 'build', 'linux', '--release'])
        if result.returncode != 0:
            raise AssertionError(result.stdout)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root)

    def test_H18_release_never_uses_debug_bundle(self):
        base = self.root / 'vsts/echo/build/linux/x64'
        shutil.copytree(base / 'release/bundle', base / 'debug/bundle')
        (base / 'release').rename(base / 'hidden-release')
        self.addCleanup((base / 'hidden-release').rename, base / 'release')
        result = configure(self.root, 'missing-release')
        self.assertNotEqual(0, result.returncode, result.stdout)
        expected = str(base / 'release/bundle/lib/libflutter_linux_gtk.so')
        self.assertIn('Flutter editor file not found: ' + expected, ' '.join(result.stdout.split()))
        self.assertIn('Run: flutter build linux --release', result.stdout)
        self.assertIn('Set FLUTTER_VST3_NATIVE_UI_ONLY=ON to build with native sliders.', result.stdout)

    def test_H19_missing_ephemeral_is_fatal(self):
        path = self.root / 'vsts/echo/linux/flutter/ephemeral'
        path.rename(path.with_name('hidden-ephemeral'))
        self.addCleanup(path.with_name('hidden-ephemeral').rename, path)
        result = configure(self.root, 'missing-ephemeral')
        self.assertNotEqual(0, result.returncode, result.stdout)
        self.assertIn('Flutter editor file not found: ' + str(path / 'flutter_linux/flutter_linux.h'),
                      ' '.join(result.stdout.split()))

    def test_H19_runpath_is_origin_relative(self):
        result = configure(self.root, 'with-flutter')
        self.assertEqual(0, result.returncode, result.stdout)
        result = command(self.root, ['cmake', '--build', 'with-flutter', '--parallel', '4'])
        self.assertEqual(0, result.returncode, result.stdout)
        plugins = list((self.root / 'with-flutter/VST3').rglob('echo.so'))
        self.assertEqual(1, len(plugins))
        result = command(self.root, ['readelf', '-d', str(plugins[0])])
        self.assertEqual(0, result.returncode, result.stdout)
        paths = re.findall(r'\(RUNPATH\).*?\[(.*?)\]', result.stdout)
        self.assertEqual(['$ORIGIN'], paths)


if __name__ == '__main__':
    unittest.main()
