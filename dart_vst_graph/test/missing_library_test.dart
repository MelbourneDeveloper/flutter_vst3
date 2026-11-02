import 'dart:io';
import 'package:dart_vst_graph/dart_vst_graph.dart';
import 'package:test/test.dart';

/// Verifies loader errors name the requested graph library.
void main() {
  test('M14 missing graph library throws with attempted library name', () {
    final directory = Directory.systemTemp.createTempSync('graph_missing_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/missing_libdart_vst_graph.so';
    expect(File(path).existsSync(), isFalse);
    expect(() => VstGraph(sampleRate: 48000, maxBlock: 512, dylibPath: path),
        throwsA(isA<ArgumentError>().having(
            (error) => error.toString(), 'loader error', contains(path))));
  });
}
