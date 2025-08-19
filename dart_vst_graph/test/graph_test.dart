import 'dart:io';
import 'package:test/test.dart';
import 'package:dart_vst_graph/dart_vst_graph.dart';

void main() {
  // Determine if the native library is present in the working
  // directory. On CI or developer machines the library should be
  // built into libdart_vst_host.{so,dylib,dll} alongside the tests.
  final libFile = Platform.isWindows
      ? File('dart_vst_host.dll')
      : Platform.isMacOS
          ? File('libdart_vst_host.dylib')
          : File('libdart_vst_host.so');

  if (!libFile.existsSync()) {
    throw Exception('Native library ${libFile.path} not found! Build the native library first.');
  }

  late VstGraph graph;
  setUp(() {
    final absolutePath = Directory.current.path + Platform.pathSeparator + libFile.path;
    graph = VstGraph(sampleRate: 48000, maxBlock: 512, dylibPath: absolutePath);
  });
  tearDown(() {
    graph.dispose();
  });

  test('gain node parameters', () {
    final id = graph.addGain(0.0);
    // The GainNode has exactly one parameter at index 0
    expect(graph.setParam(id, 0, 0.5), isTrue);
  });
}