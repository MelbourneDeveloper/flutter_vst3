import 'dart:io';

/// Finds an explicit plugin or builds the SDK's real ADelay plugin for hosting.
///
/// Test files run in parallel, so each passes its own [name] for a build folder.
String pluginFixture(String name) =>
    Platform.environment['VST3_TEST_PLUGIN'] ?? _buildSdkPlugin(name);

String _buildSdkPlugin(String name) {
  final sdk = Platform.environment['VST3_SDK_DIR'] ??
      (throw StateError(
          'Set VST3_SDK_DIR to build ADelay, or VST3_TEST_PLUGIN'));
  final build = Directory('build/test-sdk/$name').absolute.path;
  _run([
    '-S',
    sdk,
    '-B',
    build,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DSMTG_ENABLE_VSTGUI_SUPPORT=OFF',
    '-DSMTG_CREATE_PLUGIN_LINK=OFF',
    '-DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=OFF'
  ]);
  _run(['--build', build, '--target', 'adelay', '--parallel', '2']);
  final plugin = Directory('$build/VST3/Release/adelay.vst3');
  return plugin.existsSync()
      ? plugin.path
      : (throw StateError('ADelay build did not produce ${plugin.path}'));
}

void _run(List<String> arguments) {
  final result = Process.runSync('cmake', arguments);
  result.exitCode == 0
      ? null
      : throw StateError(
          'cmake ${arguments.join(' ')} failed (${result.exitCode})\n'
          '${result.stdout}\n${result.stderr}');
}
