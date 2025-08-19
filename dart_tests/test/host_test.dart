import 'dart:io';
import 'package:test/test.dart';
import 'package:dart_vst_host/dart_vst_host.dart';

void main() {
  // Only run tests when the native library is present
  final libFile = Platform.isWindows
      ? File('dart_vst_host.dll')
      : Platform.isMacOS
          ? File('libdart_vst_host.dylib')
          : File('libdart_vst_host.so');
  if (!libFile.existsSync()) {
    return;
  }

  test('load missing plug‑in throws', () {
    final host = VstHost.create(sampleRate: 48000, maxBlock: 512);
    try {
      expect(() => host.load('/nonexistent/plugin.vst3'), throwsA(isA<StateError>()));
    } finally {
      host.dispose();
    }
  });
}