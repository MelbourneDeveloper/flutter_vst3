import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo/src/echo_parameters.dart';
import 'package:echo/src/echo_processor.dart';

(Float32List, Float32List) _render(double feedback) {
  final dsp = EchoProcessor()..initialize(1000, 128);
  final parameters = EchoParameters()
    ..delayTime = 0.01
    ..feedback = feedback
    ..mix = 1;
  final input = Float32List(101)..[0] = 0.1;
  final left = Float32List(101), right = Float32List(101);
  dsp.processStereo(input, Float32List(101), left, right, parameters);
  return (left, right);
}

void _assertRepeats(double feedback) {
  final (left, right) = _render(feedback);
  var amplitude = Float32List.fromList([0.1])[0];
  for (var repeat = 1; repeat <= 10; repeat++) {
    expect(left[repeat * 10], closeTo(amplitude, 1e-8));
    expect(right[repeat * 10], closeTo(amplitude * 0.1, 1e-8));
    amplitude *= feedback * 0.85;
  }
  expect(left[20] / left[10], closeTo(feedback * 0.85, 1e-7));
  expect(left.where((x) => x != 0).length, feedback == 0 ? 1 : 10);
}

void main() {
  for (final feedback in [0.0, 1.0]) {
    test('quiet repeats at feedback $feedback retain capped decay',
        () => _assertRepeats(feedback));
  }
}
