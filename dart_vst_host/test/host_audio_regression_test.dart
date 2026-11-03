import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:test/test.dart';

import 'host_test_harness.dart';

/// Verifies real native plugin loading and exact stereo processing.
void main() {
  test('T6 T7 real ADelay returns exact one-sample delayed stereo impulse', () {
    final plugin = loadFixture('audio');
    expect(plugin.setParamNormalized(100, 0), isTrue);
    _assertImpulse(resumePlugin(plugin));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

void _assertImpulse(VstPlugin plugin) {
  final (left, right) = renderStereoImpulse(plugin);
  final expected = List<double>.filled(512, 0)..[1] = 0.5;
  expect(left, orderedEquals(expected));
  expect(right, orderedEquals(expected));
}
