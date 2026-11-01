import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_vst_host/dart_vst_host.dart';
import 'plugin_fixture.dart';

String _libraryPath() => File(switch (Platform.operatingSystem) {
      'windows' => 'dart_vst_host.dll',
      'macos' => 'libdart_vst_host.dylib',
      'linux' => 'libdart_vst_host.so',
      _ => throw UnsupportedError('Unsupported platform'),
    })
        .absolute
        .path;

VstHost _host() =>
    VstHost.create(sampleRate: 48000, maxBlock: 512, dylibPath: _libraryPath());

void main() {
  test('load missing plugin throws', () {
    final host = _host();
    addTearDown(host.dispose);
    expect(() => host.load(File('missing-plugin.vst3').absolute.path),
        throwsA(isA<StateError>()));
  });

  test('loads a real plugin and processes stereo audio', () {
    final path = pluginFixture();
    final host = _host();
    addTearDown(host.dispose);
    final plugin = host.load(path);
    addTearDown(plugin.unload);
    expect(plugin.resume(sampleRate: 48000, maxBlock: 512), isTrue);
    addTearDown(plugin.suspend);
    _process(plugin);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('real SDK plugin exposes controller parameters', () {
    final host = _host();
    addTearDown(host.dispose);
    final plugin = host.load(pluginFixture());
    addTearDown(plugin.unload);
    expect(plugin.paramCount(), greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

void _process(VstPlugin plugin) {
  final input = Float32List(512)..[0] = 0.5;
  final left = Float32List(512)..fillRange(0, 512, double.nan);
  final right = Float32List(512)..fillRange(0, 512, double.nan);
  expect(plugin.processStereoF32(input, input, left, right), isTrue);
  expect(left.every((sample) => sample.isFinite), isTrue);
  expect(right.every((sample) => sample.isFinite), isTrue);
}
