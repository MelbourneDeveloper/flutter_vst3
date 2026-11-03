import 'dart:io';
import 'dart:typed_data';
import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:test/test.dart';
import 'plugin_fixture.dart';

/// Verifies real native plugin loading and exact stereo processing.
void main() {
  test('T6 T7 real ADelay returns exact one-sample delayed stereo impulse', () {
    final host = VstHost.create(sampleRate: 48000, maxBlock: 512,
        dylibPath: File(_library()).absolute.path);
    addTearDown(host.dispose);
    final plugin = host.load(pluginFixture());
    addTearDown(plugin.unload);
    expect(plugin.setParamNormalized(100, 0), isTrue);
    expect(plugin.resume(sampleRate: 48000, maxBlock: 512), isTrue);
    addTearDown(plugin.suspend);
    _assertImpulse(plugin);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

String _library() => switch (Platform.operatingSystem) {
      'linux' => 'libdart_vst_host.so',
      'macos' => 'libdart_vst_host.dylib',
      'windows' => 'dart_vst_host.dll',
      _ => throw UnsupportedError('Unsupported platform'),
    };

void _assertImpulse(VstPlugin plugin) {
  final input = Float32List(512)..[0] = 0.5;
  final left = Float32List(512)..fillRange(0, 512, double.nan);
  final right = Float32List(512)..fillRange(0, 512, double.nan);
  expect(plugin.processStereoF32(input, input, left, right), isTrue);
  final expected = List<double>.filled(512, 0)..[1] = 0.5;
  expect(left, orderedEquals(expected));
  expect(right, orderedEquals(expected));
}
