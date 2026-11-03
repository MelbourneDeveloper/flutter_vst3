import 'dart:io';
import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:test/test.dart';

import 'host_test_harness.dart';

void main() {
  test('load missing plugin throws', () {
    final host = createHost();
    expect(() => host.load(File('missing-plugin.vst3').absolute.path),
        throwsA(isA<StateError>()));
  });

  test('loads a real plugin and processes stereo audio', () {
    _process(resumePlugin(loadFixture('host')));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('real SDK plugin exposes controller parameters', () {
    expect(loadFixture('host').paramCount(), greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

void _process(VstPlugin plugin) {
  final (left, right) = renderStereoImpulse(plugin);
  expect(left.every((sample) => sample.isFinite), isTrue);
  expect(right.every((sample) => sample.isFinite), isTrue);
}
