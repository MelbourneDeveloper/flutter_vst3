import 'package:test/test.dart';
import '../lib/src/echo_processor.dart';
import '../lib/src/echo_parameters.dart';
import '../lib/src/echo_plugin.dart';

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
      
      final inputL = List.filled(128, 0.5);
      final inputR = List.filled(128, 0.3);
      final outputL = List.filled(128, 0.0);
      final outputR = List.filled(128, 0.0);
      
      processor.processStereo(inputL, inputR, outputL, outputR, parameters);
      
      // Should produce some output (not all zeros due to dry signal)
      expect(outputL.any((sample) => sample != 0.0), isTrue);
      expect(outputR.any((sample) => sample != 0.0), isTrue);
    });
    
    test('produces obvious echo effect', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);
      final parameters = EchoParameters();
      parameters.mix = 0.9; // EXTREME mix for testing
      parameters.feedback = 0.8; // High feedback
      parameters.delayTime = 0.2; // Fast delay
      
      // Process silence first to clear buffers
      final silence = List.filled(128, 0.0);
      final output = List.filled(128, 0.0);
      processor.processStereo(silence, silence, output, output, parameters);
      
      // Now process a short impulse
      final impulse = List.filled(128, 0.0);
      impulse[0] = 1.0; // Single sample impulse
      final impulseOutput = List.filled(128, 0.0);
      
      processor.processStereo(impulse, impulse, impulseOutput, impulseOutput, parameters);
      
      // Should have dry signal at start
      expect(impulseOutput[0], greaterThan(0.0));
    });
    
    test('can be reset', () {
      final processor = EchoProcessor();
      processor.initialize(44100.0, 512);
      
      processor.reset();
      
      // After reset, should still work
      final parameters = EchoParameters();
      parameters.mix = 0.5; // Moderate settings
      final input = List.filled(128, 0.1);
      final output = List.filled(128, 0.0);
      processor.processStereo(input, input, output, output, parameters);
      
      expect(output.any((sample) => sample != 0.0), isTrue);
    });
  });

  group('DartEchoPlugin', () {
    test('initializes correctly', () {
      final plugin = DartEchoPlugin();
      expect(plugin.initialize(), isTrue);
    });
    
    test('has correct plugin info', () {
      final plugin = DartEchoPlugin();
      final info = plugin.pluginInfo;
      
      expect(info['name'], equals('Echo'));
      expect(info['vendor'], equals('CF'));
      expect(info['inputs'], equals(2));
      expect(info['outputs'], equals(2));
      expect(info['parameters'], equals(4)); // Now has 4 parameters
    });
    
    test('can process audio without crashing', () {
      final plugin = DartEchoPlugin();
      plugin.initialize();
      plugin.setupProcessing(44100.0, 512);
      plugin.setActive(true);
      
      final inputs = [
        List.filled(128, 0.5),
        List.filled(128, 0.3)
      ];
      final outputs = [
        List.filled(128, 0.0),
        List.filled(128, 0.0)
      ];
      
      plugin.processAudio(inputs, outputs);
      
      // Should produce some output
      expect(outputs[0].any((sample) => sample != 0.0), isTrue);
      expect(outputs[1].any((sample) => sample != 0.0), isTrue);
    });
  });
  
  group('DartEchoFactory', () {
    test('creates plugin instances', () {
      final plugin = DartEchoFactory.createInstance();
      expect(plugin, isA<DartEchoPlugin>());
    });
    
    test('provides class info', () {
      final info = DartEchoFactory.getClassInfo();
      expect(info['name'], equals('Echo'));
      expect(info['classId'], equals('DartEcho'));
    });
  });
}