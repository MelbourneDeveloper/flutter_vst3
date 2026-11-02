import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reverb/src/reverb_processor.dart';

(Float32List, Float32List) _render(double rate, double room, double damping) {
  final dsp = ReverbProcessor()..initialize(rate, 512);
  for (final entry in {0: room, 1: damping, 2: 1.0, 3: 0.0}.entries) {
    dsp.setParameter(entry.key, entry.value);
  }
  final input = Float32List(100000)..[0] = 1;
  final left = Float32List(input.length), right = Float32List(input.length);
  dsp.processStereo(input, input, left, right);
  return (left, right);
}

double _energy(Float32List samples, int start) =>
    samples.skip(start).fold(0.0, (sum, x) => sum + x * x);

double _differenceEnergy(Float32List samples) {
  var sum = 0.0;
  for (var i = 30000; i < samples.length; i++) {
    final difference = samples[i] - samples[i - 1];
    sum += difference * difference;
  }
  return sum;
}

void _landmarks(double rate) {
  final (left, right) = _render(rate, 0, 0);
  final scale = rate / 44100;
  for (final (samples, spread) in [(left, 0), (right, 23)]) {
    final onset = ((1116 + spread) * scale).round();
    expect(samples.take(onset).toList(), List.filled(onset, 0.0));
    // Four allpasses each invert the direct impulse: (-1)^4 = 1.
    expect(samples[onset], 1.0);
    expect(samples[((1188 + spread) * scale).round()], 1.0);
    // The shortest allpass's first delayed impulse has opposite sign.
    expect(samples[onset + ((225 + spread) * scale).round()], -1.0);
  }
}

void _roomDecay() {
  final small = _render(44100, 0, 0.5);
  final large = _render(44100, 1, 0.5);
  for (final (a, b) in [(small.$1, large.$1), (small.$2, large.$2)]) {
    expect(_energy(b, 50000), greaterThan(_energy(a, 50000) * 100));
    expect(_energy(a, 50000), greaterThan(0));
  }
}

void _dampingDecay() {
  final bright = _render(44100, 0.8, 0);
  final dark = _render(44100, 0.8, 0.8);
  for (final (a, b) in [(bright.$1, dark.$1), (bright.$2, dark.$2)]) {
    expect(_differenceEnergy(b), lessThan(_differenceEnergy(a) * 0.1));
    expect(_differenceEnergy(b), greaterThan(0));
  }
}

void _allpassReference() {
  final filter = AllpassFilter(2);
  // H(z) = -1 + z^-2 / (1 - 0.5 z^-2).
  final actual = [for (final x in [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) filter.process(x)];
  expect(actual, [-1, 0, 1, 0, 0.5, 0, 0.25]);
  filter.reset();
  expect(filter.process(0), 0);
}

void _combReference() {
  for (final room in [0.0, 1.0]) {
    for (final damping in [0.0, 0.75]) {
      final feedback = 0.7 + room * 0.28;
      final comb = CombFilter(4)
        ..setFeedback(feedback)
        ..setDampening(damping);
      final actual = [for (var i = 0; i < 11; i++) comb.process(i == 0 ? 1 : 0)];
      final first = feedback * (1 - damping);
      final expected = [0, 0, 0, 0, 1, 0, 0, 0,
        first, first * damping, first * damping * damping];
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i], closeTo(expected[i], 1e-7));
      }
    }
  }
}

void main() {
  for (final rate in [44100.0, 96000.0]) {
    test('wet only stereo landmarks at $rate', () => _landmarks(rate));
  }
  test('large room retains more late energy on both channels', _roomDecay);
  test('damping absorbs high frequency late tail on both channels', _dampingDecay);
  test('allpass independent two sample delay reference', _allpassReference);
  test('comb feedback and damping independent reference', _combReference);
}
