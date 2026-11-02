"""Verify declared SDK floors cover the APIs used by the Flutter UI."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


def floor(source, key):
    match = re.search(r'^  ' + key + r':\s*[\'\"]?[>=^]*(\d+)\.(\d+)\.(\d+)', source, re.M)
    if match is None:
        raise AssertionError('Missing version floor for ' + key)
    return tuple(map(int, match.groups()))


class VersionFloors(unittest.TestCase):
    def test_M7_sdk_floors_cover_new_color_and_slider_APIs(self):
        for package in ('flutter_vst3', 'vsts/echo'):
            source = (ROOT / package / 'pubspec.yaml').read_text()
            with self.subTest(package=package):
                self.assertGreaterEqual(floor(source, 'sdk'), (3, 6, 0))
                self.assertGreaterEqual(floor(source, 'flutter'), (3, 27, 0))


if __name__ == '__main__':
    unittest.main()
