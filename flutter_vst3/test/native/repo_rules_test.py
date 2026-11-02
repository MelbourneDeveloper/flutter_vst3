"""Regression checks for deliberately removed APIs and artifacts."""
import pathlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


def text(path):
    return (ROOT / path).read_text(encoding='utf-8')


class RemovedDesignTests(unittest.TestCase):
    def test_H9_registration_removed_and_migration_recorded(self):
        for folder in ('flutter_vst3/lib', 'vsts/echo/lib'):
            for path in (ROOT / folder).rglob('*.dart'):
                self.assertNotIn('registerProcessor', path.read_text(), str(path))
        self.assertNotIn('registerProcessor', text('flutter_vst3/README.md'))
        self.assertIn('Removed obsolete same-process VST3Bridge registration and FFI callbacks',
                      text('flutter_vst3/CHANGELOG.md'))

    def test_M2_dead_processor_removed(self):
        self.assertNotIn('VST3AudioProcessor', text('flutter_vst3/lib/src/parameter_binding.dart'))

    def test_M3_waveform_work_removed(self):
        self.assertNotIn('waveformBuffer', text('vsts/echo/lib/src/echo_processor.dart'))

    def test_M4_shared_process_claim_removed(self):
        self.assertNotRegex(text('vsts/echo/lib/ui/echo_ui.dart'),
                            r'(?i)(same|shared)\s+process')

    def test_M8_embedder_files_removed(self):
        self.assertEqual([], list((ROOT / 'flutter_vst3/native').rglob('flutter_embedder*.cpp')))
        self.assertEqual([], list((ROOT / 'flutter_vst3/native').rglob('flutter_embedder.h')))

    def test_M9_plugin_view_removed(self):
        self.assertEqual([], list((ROOT / 'flutter_vst3/native').rglob('plugin_view.cpp')))

    def test_M10_no_tracked_native_binaries(self):
        names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).split(b'\0')
        magic = {b'\x7fELF', b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
                 b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe',
                 b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
        for name in filter(None, names):
            path = ROOT / name.decode()
            with path.open('rb') as source:
                self.assertNotIn(source.read(4), magic, str(path))

    def test_H16_own_objc_classes_are_prefixed(self):
        files = list((ROOT / 'flutter_vst3/native').rglob('*'))
        source = '\n'.join(p.read_text() for p in files if p.suffix in ('.h', '.mm'))
        classes = re.findall(r'@interface\s+(\w+)', source)
        self.assertGreaterEqual(len(classes), 3)
        for name in classes:
            self.assertRegex(source, r'#define\s+' + name +
                             r'\s+CONCAT\(' + name + r',\s*PLUGIN_TARGET_NAME\)')

    def test_M11_no_ephemeral_or_user_config_paths(self):
        names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
        for name in filter(None, names):
            self.assertNotRegex(name, r'Flutter/ephemeral/')
            if pathlib.Path(name).suffix in ('.json', '.yaml', '.yml', '.cmake'):
                self.assertNotRegex(text(name), r'/Users/|/home/[^$\s/]+/|[A-Za-z]:[\\\\/]Users[\\\\/]')

    def test_M13_no_same_isolate_requirement(self):
        self.assertNotRegex(text('FLUTTER_UI_SPEC.md'), r'(?i)non.negotiable')

    def test_M12_echo_readme_not_template(self):
        self.assertNotIn('A new Flutter project.', text('vsts/echo/README.md'))
        self.assertNotIn('This project is a starting point', text('vsts/echo/README.md'))

    def test_M15_only_allowlisted_error_prints(self):
        allowed = {
            'std::fprintf(stderr, "{{PLUGIN_ID}}: %s\\n", error.what());',
            'fprintf(stderr, "flutter_vst3: gtk_plug_new failed. VST3 GUI embedding on Linux requires an X11 backend (GDK_BACKEND=x11).\\n");',
            'NSLog(@"[flutter_vst3] Flutter app library failed to load: %s", dlerror());',
            'NSLog(@"[flutter_vst3] Flutter UI mount exception: %@. Falling back to Cocoa.", e);',
            'NSLog(@"[flutter_vst3] FlutterEngine failed to launch (e.g. Dart SDK hash mismatch). Falling back to Cocoa.");',
        }
        for folder in ('src', 'templates'):
            for path in (ROOT / 'flutter_vst3/native' / folder).rglob('*'):
                if path.is_file():
                    for line in path.read_text().splitlines():
                        if re.search(r'(?<![\w])(?:printf|fprintf|NSLog)\s*\(|std::(?:cout|cerr)', line):
                            self.assertIn(line.strip(), allowed, str(path))

    def test_M18_block_automation_documented(self):
        self.assertIn('Parameters apply per block, so only the last point in each queue is used.',
                      text('flutter_vst3/native/templates/plugin_processor_aot.cpp.template'))

    def test_M19_no_untrue_performance_claims(self):
        for path in (ROOT / 'flutter_vst3/native').rglob('*'):
            if path.is_file():
                self.assertNotRegex(path.read_text(), r'(?i)zero-copy|lock-free', str(path))

    def test_T5_no_workspace_paths(self):
        for folder in ('dart_vst_host/test', 'dart_vst_graph/test', 'flutter_vst3/test'):
            for path in (ROOT / folder).rglob('*.dart'):
                self.assertNotIn('/workspace', path.read_text(), str(path))


class AgentSetup(unittest.TestCase):
    def test_standard_make_targets_exist(self):
        for target in ('lint', 'fmt', 'ci', 'setup', 'test', 'build', 'clean'):
            result = subprocess.run(['make', '-n', target], cwd=ROOT, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            self.assertEqual(0, result.returncode, target + ': ' + result.stdout)
            self.assertTrue(result.stdout.strip(), target + ' does nothing')

    def test_agent_files_point_at_one_canonical_file(self):
        self.assertIn('CLAUDE.md', (ROOT / 'AGENTS.md').read_text())
        self.assertLess(len((ROOT / 'AGENTS.md').read_text().splitlines()), 10, 'AGENTS.md is a pointer')


if __name__ == '__main__':
    unittest.main()
