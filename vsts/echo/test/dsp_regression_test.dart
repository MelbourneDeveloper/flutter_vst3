import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo/src/echo_processor.dart';

import 'echo_test_harness.dart';

void main() {
  for (final rate in [44100, 96000, 192000]) {
    for (final delay in [0.0, 0.25, 1.0]) {
      test('impulse timing $rate $delay', () {
        final (dsp, params) =
            echoDsp(rate.toDouble(), 512, delayTime: delay, feedback: 0);
        final position = (rate * delay).round();
        final input = Float32List(position + 2)..[0] = 1;
        final output = Float32List(input.length);
        dsp.processStereo(input, Float32List(input.length), output,
            Float32List(input.length), params);
        expect(output[position], 1);
        expect(output.where((x) => x != 0).length, 1);
      });
    }
  }
  test('bypass records incoming audio and advances tail', () {
    final (dsp, params) = echoDsp(1000, 512, delayTime: 0.01, feedback: 0);
    params.bypass = 1;
    final first = Float32List(5)..[0] = 1;
    dsp.processStereo(first, Float32List(5), Float32List(5), Float32List(5), params);
    params.bypass = 0;
    final output = Float32List(10);
    dsp.processStereo(Float32List(10), Float32List(10), output,
        Float32List(10), params);
    expect(output[5], 1);
    expect(output.where((x) => x != 0).length, 1);
  });

  test('H23: saturation has continuous value and slope at the threshold', () {
    const h = 1e-6;
    for (final edge in [1.0, -1.0]) {
      final below = EchoProcessor.softSaturate(edge * (1 - h));
      final above = EchoProcessor.softSaturate(edge * (1 + h));
      expect(above - below, closeTo(edge * 2 * h, 1e-9));
    }
    expect(EchoProcessor.softSaturate(0.5), 0.5, reason: 'unity below the threshold');
    expect(EchoProcessor.softSaturate(1e9), lessThan(2.0));
    expect(EchoProcessor.softSaturate(-1e9), greaterThan(-2.0));
  });

  test('H23: maximum feedback stays bounded over 10 seconds of loud input', () {
    const rate = 48000.0;
    const block = 480;
    final (processor, parameters) =
        echoDsp(rate, block, delayTime: 0.01, feedback: 1.0);
    final input = Float32List(block)..fillRange(0, block, 1.0);
    final outL = Float32List(block);
    final outR = Float32List(block);
    for (var n = 0; n < 1000; n++) {
      processor.processStereo(input, input, outL, outR, parameters);
      expect(outL.every((s) => s.isFinite && s.abs() < 10.0), isTrue);
    }
  });

  test('moving the delay is smoothed, with no jump in the output', () {
    const rate = 48000.0;
    const block = 64;
    final (processor, parameters) =
        echoDsp(rate, block, delayTime: 0.1, feedback: 0.0);
    final inputL = Float32List(block);
    final outL = Float32List(block);
    final outR = Float32List(block);
    var phase = 0;
    double? previous;
    var largestStep = 0.0;
    for (var n = 0; n < 3000; n++) {
      parameters.delayTime = n < 1500 ? 0.1 : 0.2;
      for (var i = 0; i < block; i++) {
        inputL[i] = math.sin(2 * math.pi * 100 * phase++ / rate);
      }
      processor.processStereo(inputL, inputL, outL, outR, parameters);
      for (var i = 0; n > 1000 && i < block; i++) {
        final step = previous == null ? 0.0 : (outL[i] - previous).abs();
        largestStep = step > largestStep ? step : largestStep;
        previous = outL[i];
      }
    }
    expect(largestStep, lessThan(0.08), reason: 'an unsmoothed jump is near 1');
  });

  test('zero delay passes input through with no stale samples', () {
    final (processor, parameters) =
        echoDsp(48000, 64, delayTime: 0.0, feedback: 0.0);
    final input = Float32List(64)..fillRange(0, 64, 0.5);
    final outL = Float32List(64);
    final outR = Float32List(64);
    processor.processStereo(input, input, outL, outR, parameters);
    expect(outL[10], closeTo(0.55, 1e-6), reason: 'L plus 10% of R crossfeed');
  });
}
