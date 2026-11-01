import 'dart:io';
import 'package:test/test.dart';
import 'package:dart_vst_graph/dart_vst_graph.dart';

String _libraryName(String package) => switch (Platform.operatingSystem) {
      'windows' => '$package.dll',
      'macos' => 'lib$package.dylib',
      'linux' => 'lib$package.so',
      _ => throw UnsupportedError('Unsupported platform'),
    };

void main() {
  test('gain node parameters', () {
    final graph = VstGraph(
        sampleRate: 48000,
        maxBlock: 512,
        dylibPath: File(_libraryName('dart_vst_graph')).absolute.path);
    addTearDown(graph.dispose);
    final id = graph.addGain(0.0);
    expect(graph.setParam(id, 0, 0.5), isTrue);
  });

  test('missing explicit library fails with its path', () {
    final path = File('missing-graph-library').absolute.path;
    expect(
        () => VstGraph(sampleRate: 48000, maxBlock: 512, dylibPath: path),
        throwsA(isA<ArgumentError>()
            .having((e) => '$e', 'message', contains(path))));
  });

  test('default loader never substitutes the host library', () {
    final temp = Directory.systemTemp.createTempSync('graph-loader-');
    addTearDown(() => temp.deleteSync(recursive: true));
    _copyHost(temp);
    final probe = File('${temp.path}/probe.dart')
      ..writeAsStringSync(
          "import '${File('lib/src/bindings.dart').absolute.uri}';\n"
          'void main() { VstGraph(sampleRate: 48000, maxBlock: 512); }\n');
    final result = _probe(probe, temp);
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains(_libraryName('dart_vst_graph')));
  });
}

void _copyHost(Directory temp) {
  final host = File('../dart_vst_host/${_libraryName('dart_vst_host')}');
  host.copySync('${temp.path}/${_libraryName('dart_vst_host')}');
}

ProcessResult _probe(File script, Directory temp) => Process.runSync(
    Platform.resolvedExecutable,
    [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      script.path
    ],
    workingDirectory: temp.path,
    environment: {
      'LD_LIBRARY_PATH': temp.path,
      'DYLD_LIBRARY_PATH': temp.path,
      'PATH': '${temp.path}${Platform.isWindows ? ';' : ':'}'
          '${Platform.environment['PATH']}',
    });
