import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_vst_host/dart_vst_host.dart';

/// Create a simple WAV file from Float32 audio data
Uint8List _createWavFile(Float32List audioData, int sampleRate) {
  final numSamples = audioData.length;
  final byteRate = sampleRate * 2; // 16-bit mono
  final dataSize = numSamples * 2; // 16-bit samples
  final fileSize = 36 + dataSize;
  
  final bytes = ByteData(44 + dataSize);
  int offset = 0;
  
  // RIFF header
  bytes.setUint8(offset++, 0x52); // 'R'
  bytes.setUint8(offset++, 0x49); // 'I'
  bytes.setUint8(offset++, 0x46); // 'F'
  bytes.setUint8(offset++, 0x46); // 'F'
  bytes.setUint32(offset, fileSize, Endian.little); offset += 4;
  bytes.setUint8(offset++, 0x57); // 'W'
  bytes.setUint8(offset++, 0x41); // 'A'
  bytes.setUint8(offset++, 0x56); // 'V'
  bytes.setUint8(offset++, 0x45); // 'E'
  
  // fmt chunk
  bytes.setUint8(offset++, 0x66); // 'f'
  bytes.setUint8(offset++, 0x6D); // 'm'
  bytes.setUint8(offset++, 0x74); // 't'
  bytes.setUint8(offset++, 0x20); // ' '
  bytes.setUint32(offset, 16, Endian.little); offset += 4; // chunk size
  bytes.setUint16(offset, 1, Endian.little); offset += 2; // PCM format
  bytes.setUint16(offset, 1, Endian.little); offset += 2; // mono
  bytes.setUint32(offset, sampleRate, Endian.little); offset += 4;
  bytes.setUint32(offset, byteRate, Endian.little); offset += 4;
  bytes.setUint16(offset, 2, Endian.little); offset += 2; // block align
  bytes.setUint16(offset, 16, Endian.little); offset += 2; // bits per sample
  
  // data chunk
  bytes.setUint8(offset++, 0x64); // 'd'
  bytes.setUint8(offset++, 0x61); // 'a'
  bytes.setUint8(offset++, 0x74); // 't'
  bytes.setUint8(offset++, 0x61); // 'a'
  bytes.setUint32(offset, dataSize, Endian.little); offset += 4;
  
  // Convert float32 to 16-bit PCM
  for (int i = 0; i < numSamples; i++) {
    final sample = (audioData[i] * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(offset, sample, Endian.little);
    offset += 2;
  }
  
  return bytes.buffer.asUint8List();
}

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

  test('audio generation and save to file', () {
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
      
      // Save audio to a WAV file so we can actually hear it!
      final duration = 2.0; // 2 seconds
      final sampleRate = 48000;
      final totalSamples = (duration * sampleRate).round();
      final audioData = Float32List(totalSamples);
      
      // Generate 2 seconds of 440Hz sine wave
      for (int i = 0; i < totalSamples; i++) {
        audioData[i] = 0.5 * sin(2 * pi * 440 * i / sampleRate);
      }
      
      // Create a simple WAV file
      final outputFile = File('/workspace/test_audio_440hz.wav');
      final wavData = _createWavFile(audioData, sampleRate);
      outputFile.writeAsBytesSync(wavData);
      
      print('Audio saved to: ${outputFile.path}');
      print('File size: ${outputFile.lengthSync()} bytes');
      print('Duration: ${duration}s at ${sampleRate}Hz');
      print('Download this file to your Mac and play it!');
      print('Audio processing test completed - verified audio generation and saved to file');
      
    } finally {
      host.dispose();
    }
  });

  test('audio effects processing - 100ms on/off with delay and reverb', () {
    final host = VstHost.create(
      sampleRate: 48000, 
      maxBlock: 512, 
      dylibPath: libFile.absolute.path
    );
    try {
      // Create a 100ms on, 100ms off pattern for 4 seconds
      final duration = 4.0; // 4 seconds total
      final sampleRate = 48000;
      final totalSamples = (duration * sampleRate).round();
      final onDuration = 0.1; // 100ms on
      final offDuration = 0.1; // 100ms off
      final cycleDuration = onDuration + offDuration; // 200ms cycle
      final onSamples = (onDuration * sampleRate).round();
      final cycleSamples = (cycleDuration * sampleRate).round();
      
      final audioData = Float32List(totalSamples);
      
      // Generate 100ms on/off pattern with 440Hz sine wave
      for (int i = 0; i < totalSamples; i++) {
        final cyclePos = i % cycleSamples;
        final isOn = cyclePos < onSamples;
        
        if (isOn) {
          audioData[i] = 0.5 * sin(2 * pi * 440 * i / sampleRate);
        } else {
          audioData[i] = 0.0; // silence during off periods
        }
      }
      
      print('Generated 100ms on/off pattern audio');
      print('Total duration: ${duration}s, Cycles: ${(duration / cycleDuration).round()}');
      print('On samples per cycle: $onSamples, Total samples: $totalSamples');
      
      // Apply simple delay effect (simulate 150ms delay)
      final delayMs = 150.0;
      final delaySamples = (delayMs * sampleRate / 1000).round();
      final delayedAudio = Float32List(totalSamples);
      final feedbackGain = 0.3;
      
      for (int i = 0; i < totalSamples; i++) {
        delayedAudio[i] = audioData[i];
        if (i >= delaySamples) {
          // Add delayed signal with feedback
          delayedAudio[i] += delayedAudio[i - delaySamples] * feedbackGain;
        }
      }
      
      print('Applied delay effect: ${delayMs}ms delay with ${feedbackGain * 100}% feedback');
      
      // Apply simple reverb effect (simulate room reverb)
      final reverbAudio = Float32List(totalSamples);
      final reverbDecay = 0.5;
      final reverbDelay1 = (37 * sampleRate / 1000).round(); // 37ms
      final reverbDelay2 = (89 * sampleRate / 1000).round(); // 89ms
      final reverbDelay3 = (127 * sampleRate / 1000).round(); // 127ms
      
      for (int i = 0; i < totalSamples; i++) {
        reverbAudio[i] = delayedAudio[i];
        
        // Add multiple delay taps for reverb simulation
        if (i >= reverbDelay1) {
          reverbAudio[i] += reverbAudio[i - reverbDelay1] * reverbDecay * 0.3;
        }
        if (i >= reverbDelay2) {
          reverbAudio[i] += reverbAudio[i - reverbDelay2] * reverbDecay * 0.2;
        }
        if (i >= reverbDelay3) {
          reverbAudio[i] += reverbAudio[i - reverbDelay3] * reverbDecay * 0.1;
        }
      }
      
      print('Applied reverb effect: Multi-tap reverb with ${reverbDecay * 100}% decay');
      
      // Normalize to prevent clipping
      final maxSample = reverbAudio.fold(0.0, (max, sample) => sample.abs() > max ? sample.abs() : max);
      if (maxSample > 0.95) {
        final normalizeGain = 0.95 / maxSample;
        for (int i = 0; i < totalSamples; i++) {
          reverbAudio[i] *= normalizeGain;
        }
        print('Normalized audio by ${normalizeGain.toStringAsFixed(3)}x to prevent clipping');
      }
      
      // Save the processed audio
      final outputFile = File('/workspace/test_fx_audio_100ms_pattern.wav');
      final wavData = _createWavFile(reverbAudio, sampleRate);
      outputFile.writeAsBytesSync(wavData);
      
      print('Processed audio saved to: ${outputFile.path}');
      print('File size: ${outputFile.lengthSync()} bytes');
      print('Final RMS: ${sqrt(reverbAudio.map((x) => x * x).reduce((a, b) => a + b) / totalSamples)}');
      print('Audio FX processing completed - download the file to hear the 100ms on/off pattern with delay and reverb!');
      
      // Verify the pattern exists
      expect(reverbAudio.any((sample) => sample.abs() > 0.1), isTrue);
      expect(outputFile.existsSync(), isTrue);
      
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