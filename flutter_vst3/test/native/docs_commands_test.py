"""Execute every documented individual package test command."""
import pathlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


class DocumentationCommands(unittest.TestCase):
    def test_AB4_documented_tests_execute(self):
        blocks = re.findall(r'```[^\n]*\n(.*?)```', (ROOT / 'README.md').read_text(), re.S)
        commands = re.findall(r'^\(cd [^\n]+ && (?:dart|flutter) test\)\s*$',
                              '\n'.join(blocks), re.M)
        self.assertGreaterEqual(len(commands), 4)
        packages = {re.search(r'cd (\S+)', command)[1] for command in commands}
        self.assertTrue({'flutter_vst3', 'vsts/echo', 'dart_vst_host', 'dart_vst_graph'} <= packages)
        for command in commands:
            with self.subTest(command=command):
                result = subprocess.run(['bash', '-lc', command], cwd=ROOT,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                self.assertEqual(0, result.returncode, result.stdout)
                self.assertIn('All tests passed!', result.stdout)


if __name__ == '__main__':
    unittest.main()
