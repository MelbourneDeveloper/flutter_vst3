import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:echo/src/echo_processor.dart';
import 'package:echo/src/echo_parameters.dart';

void main() {
  group('EchoProcessor', () {
    test('initializes correctly', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);

      expect(processor, isNotNull);
    });

    test('processes stereo audio without crashing', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);
      final parameters = EchoParameters();
      parameters.mix = 0.8; // High mix for obvious effect
      parameters.feedback = 0.7; // High feedback
      parameters.delayTime = 0.3; // Medium delay

      final inputL = Float32List(128)..fillRange(0, 128, 0.5);
      final inputR = Float32List(128)..fillRange(0, 128, 0.3);
      final outputL = Float32List(128);
      final outputR = Float32List(128);

      processor.processStereo(inputL, inputR, outputL, outputR, parameters);

      // Should produce some output (not all zeros due to dry signal)
      expect(outputL, everyElement(closeTo(0.1, 1e-8)));
      expect(outputR, everyElement(closeTo(0.06, 1e-8)));
    });

    test('preserves the exact dry block before the delay arrives', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);
      final parameters = EchoParameters();
      parameters.mix = 0.9; // EXTREME mix for testing
      parameters.feedback = 0.8; // High feedback
      parameters.delayTime = 0.2; // Fast delay

      // Process silence first to clear buffers
      final silence = Float32List(128);
      final output = Float32List(128);
      processor.processStereo(silence, silence, output, output, parameters);

      // Now process a short impulse
      final impulse = Float32List(128);
      impulse[0] = 1.0; // Single sample impulse
      final impulseOutput = Float32List(128);

      processor.processStereo(
          impulse, impulse, impulseOutput, impulseOutput, parameters);

      // Should have dry signal at start
      expect(impulseOutput[0], closeTo(0.1, 1e-8));
      expect(impulseOutput.skip(1), everyElement(0.0));
    });

    test('can be reset', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);

      processor.reset();

      // After reset, should still work
      final parameters = EchoParameters();
      parameters.mix = 0.5; // Moderate settings
      final input = Float32List(128)..fillRange(0, 128, 0.1);
      final output = Float32List(128);
      processor.processStereo(input, input, output, output, parameters);

      expect(output, everyElement(closeTo(0.05, 1e-8)));
    });

    test('delay automation cannot emit audio before either delay arrives', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);
      final parameters = EchoParameters()
        ..mix = 1.0
        ..feedback = 0.5
        ..delayTime = 0.1;

      final input = Float32List.fromList(
        List.generate(512, (i) => (i % 32 == 0) ? 0.8 : 0.0),
      );
      final output = Float32List(512);
      processor.processStereo(input, input, output, output, parameters);

      // Change delayTime sharply
      parameters.delayTime = 0.6;
      final output2 = Float32List(512);
      processor.processStereo(input, input, output2, output2, parameters);

      expect(output, everyElement(0.0));
      expect(output2, everyElement(0.0));
    });
  });
}
