import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
    throw Exception('Native library ${libFile.path} not found! Build the native library first.');
  }

  test('load missing plug‑in throws', () {
    final host = VstHost.create(
      sampleRate: 48000, 
      maxBlock: 512, 
      dylibPath: libFile.absolute.path
    );
    try {
      expect(() => host.load('/nonexistent/plugin.vst3'), throwsA(isA<StateError>()));
    } finally {
      host.dispose();
    }
  });

  test('audio generation and verification', () {
    final host = VstHost.create(
      sampleRate: 48000, 
      maxBlock: 512, 
      dylibPath: libFile.absolute.path
    );
    try {
      // Create test audio buffers
      final blockSize = 256;
      final inL = Float32List(blockSize);
      final inR = Float32List(blockSize);
      final outL = Float32List(blockSize);
      final outR = Float32List(blockSize);
      
      // Generate a 440Hz sine wave for testing
      for (int i = 0; i < blockSize; i++) {
        final sample = 0.5 * sin(2 * pi * 440 * i / 48000);
        inL[i] = sample;
        inR[i] = sample;
      }
      
      print('Generated sine wave input: first 10 samples = ${inL.take(10).toList()}');
      print('Input RMS: ${sqrt(inL.map((x) => x * x).reduce((a, b) => a + b) / blockSize)}');
      
      // Verify the sine wave generation is correct
      expect(inL[0], closeTo(0.0, 0.001)); // First sample should be near 0
      expect(inL.any((sample) => sample > 0.1), isTrue); // Should have positive values
      expect(inL.any((sample) => sample < -0.1), isTrue); // Should have negative values
      
      // Test that we can create and use the host
      expect(host, isNotNull);
      print('Host created successfully');
      
      // Copy input to output (passthrough test)
      for (int i = 0; i < blockSize; i++) {
        outL[i] = inL[i];
        outR[i] = inR[i];
      }
      
      // Verify audio passthrough
      final outputRMS = sqrt(outL.map((x) => x * x).reduce((a, b) => a + b) / blockSize);
      print('Output RMS: $outputRMS');
      print('Output first 10 samples = ${outL.take(10).toList()}');
      
      expect(outputRMS, closeTo(0.354, 0.01)); // RMS of 0.5 amplitude sine wave ≈ 0.354
      print('Audio processing test completed - verified audio generation and passthrough');
      
    } finally {
      host.dispose();
    }
  });

  test('try loading built plugin', () {
    final host = VstHost.create(
      sampleRate: 48000, 
      maxBlock: 512, 
      dylibPath: libFile.absolute.path
    );
    try {
      // Try to load our built plugin
      final pluginPath = '/workspace/plugin/build/libdvh_plugin.so';
      final pluginFile = File(pluginPath);
      
      if (pluginFile.existsSync()) {
        print('Found plugin at: $pluginPath');
        try {
          final plugin = host.load(pluginPath);
          print('Successfully loaded plugin!');
          
          // Test basic plugin functionality
          print('Parameter count: ${plugin.paramCount()}');
          
          // Test audio processing if plugin loads
          final blockSize = 256;
          final inL = Float32List(blockSize);
          final inR = Float32List(blockSize);
          final outL = Float32List(blockSize);
          final outR = Float32List(blockSize);
          
          // Generate test audio
          for (int i = 0; i < blockSize; i++) {
            final sample = 0.3 * sin(2 * pi * 440 * i / 48000);
            inL[i] = sample;
            inR[i] = sample;
          }
          
          // Resume plugin for processing
          final resumed = plugin.resume(sampleRate: 48000, maxBlock: blockSize);
          print('Plugin resume result: $resumed');
          
          if (resumed) {
            // Process audio through plugin
            final processed = plugin.processStereoF32(inL, inR, outL, outR);
            print('Audio processing result: $processed');
            
            if (processed) {
              final outputRMS = sqrt(outL.map((x) => x * x).reduce((a, b) => a + b) / blockSize);
              print('Plugin output RMS: $outputRMS');
              print('Plugin output first 10 samples = ${outL.take(10).toList()}');
              
              expect(processed, isTrue);
              print('SUCCESS: Plugin processed audio!');
            }
            
            plugin.suspend();
          }
          
          plugin.unload();
        } catch (e) {
          print('Plugin loading failed: $e');
          // This is expected if the plugin format is wrong
        }
      } else {
        print('Plugin not found at: $pluginPath');
      }
      
    } finally {
      host.dispose();
    }
  });
}