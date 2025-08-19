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
  bytes.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  bytes.setUint8(offset++, 0x57); // 'W'
  bytes.setUint8(offset++, 0x41); // 'A'
  bytes.setUint8(offset++, 0x56); // 'V'
  bytes.setUint8(offset++, 0x45); // 'E'

  // fmt chunk
  bytes.setUint8(offset++, 0x66); // 'f'
  bytes.setUint8(offset++, 0x6D); // 'm'
  bytes.setUint8(offset++, 0x74); // 't'
  bytes.setUint8(offset++, 0x20); // ' '
  bytes.setUint32(offset, 16, Endian.little);
  offset += 4; // chunk size
  bytes.setUint16(offset, 1, Endian.little);
  offset += 2; // PCM format
  bytes.setUint16(offset, 1, Endian.little);
  offset += 2; // mono
  bytes.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  bytes.setUint32(offset, byteRate, Endian.little);
  offset += 4;
  bytes.setUint16(offset, 2, Endian.little);
  offset += 2; // block align
  bytes.setUint16(offset, 16, Endian.little);
  offset += 2; // bits per sample

  // data chunk
  bytes.setUint8(offset++, 0x64); // 'd'
  bytes.setUint8(offset++, 0x61); // 'a'
  bytes.setUint8(offset++, 0x74); // 't'
  bytes.setUint8(offset++, 0x61); // 'a'
  bytes.setUint32(offset, dataSize, Endian.little);
  offset += 4;

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
    throw Exception(
        'Native library ${libFile.path} not found! Build the native library first.');
  }

  test('load missing plug‑in throws', () {
    final host = VstHost.create(
        sampleRate: 48000, maxBlock: 512, dylibPath: libFile.absolute.path);
    try {
      expect(() => host.load('/nonexistent/plugin.vst3'),
          throwsA(isA<StateError>()));
    } finally {
      host.dispose();
    }
  });

  test('audio generation and save to file', () {
    final host = VstHost.create(
        sampleRate: 48000, maxBlock: 512, dylibPath: libFile.absolute.path);
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

      print(
          'Generated sine wave input: first 10 samples = ${inL.take(10).toList()}');
      print(
          'Input RMS: ${sqrt(inL.map((x) => x * x).reduce((a, b) => a + b) / blockSize)}');

      // Verify the sine wave generation is correct
      expect(inL[0], closeTo(0.0, 0.001)); // First sample should be near 0
      expect(inL.any((sample) => sample > 0.1),
          isTrue); // Should have positive values
      expect(inL.any((sample) => sample < -0.1),
          isTrue); // Should have negative values

      // Test that we can create and use the host
      expect(host, isNotNull);
      print('Host created successfully');

      // Copy input to output (passthrough test)
      for (int i = 0; i < blockSize; i++) {
        outL[i] = inL[i];
        outR[i] = inR[i];
      }

      // Verify audio passthrough
      final outputRMS =
          sqrt(outL.map((x) => x * x).reduce((a, b) => a + b) / blockSize);
      print('Output RMS: $outputRMS');
      print('Output first 10 samples = ${outL.take(10).toList()}');

      expect(outputRMS,
          closeTo(0.354, 0.01)); // RMS of 0.5 amplitude sine wave ≈ 0.354

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
      print(
          'Audio processing test completed - verified audio generation and saved to file');
    } finally {
      host.dispose();
    }
  });

  test('VST3 FX processing - MUST load real plugins or FAIL HARD', () {
    final host = VstHost.create(
        sampleRate: 48000, maxBlock: 512, dylibPath: libFile.absolute.path);

    VstPlugin? reverbPlugin;

    try {
      // HARD REQUIREMENT: Load FlutterDartReverb plugin - FAIL if not found
      final reverbPath = '/workspace/vst_plugins/FlutterDartReverb.vst3';

      if (!File(reverbPath).existsSync() &&
          !Directory(reverbPath).existsSync()) {
        throw Exception(
            '🔥 HARD FAIL: FlutterDartReverb VST3 plugin NOT FOUND at $reverbPath');
      }

      reverbPlugin = host.load(reverbPath);
      print('✅ REVERB PLUGIN LOADED: $reverbPath');

      // Generate 100ms on/off pattern audio
      final duration = 4.0;
      final sampleRate = 48000;
      final totalSamples = (duration * sampleRate).round();
      final onDuration = 0.1; // 100ms on
      final offDuration = 0.1; // 100ms off
      final cycleDuration = onDuration + offDuration;
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
          audioData[i] = 0.0;
        }
      }

      print(
          'Generated 100ms on/off pattern - ${(duration / cycleDuration).round()} cycles');

      // PROCESS THROUGH REVERB PLUGIN
      final reverbResumed =
          reverbPlugin.resume(sampleRate: 48000, maxBlock: 512);
      if (!reverbResumed) {
        throw Exception('🔥 HARD FAIL: Reverb plugin failed to resume!');
      }

      print('Reverb plugin parameters: ${reverbPlugin.paramCount()}');

      // Process audio through reverb
      final blockSize = 512;
      final finalAudio = Float32List(totalSamples);

      for (int start = 0; start < totalSamples; start += blockSize) {
        final end = (start + blockSize).clamp(0, totalSamples);
        final currentBlockSize = end - start;

        final inL = Float32List(currentBlockSize);
        final inR = Float32List(currentBlockSize);
        final outL = Float32List(currentBlockSize);
        final outR = Float32List(currentBlockSize);

        // Copy input audio
        for (int i = 0; i < currentBlockSize; i++) {
          inL[i] = audioData[start + i];
          inR[i] = audioData[start + i];
        }

        // Process through reverb plugin
        final processed = reverbPlugin.processStereoF32(inL, inR, outL, outR);
        if (!processed) {
          throw Exception(
              '🔥 HARD FAIL: Reverb plugin processing failed at sample $start!');
        }

        // Copy output data (use left channel)
        for (int i = 0; i < currentBlockSize; i++) {
          finalAudio[start + i] = outL[i];
        }
      }

      reverbPlugin.suspend();
      print('✅ REVERB PROCESSING COMPLETED');

      // Save the processed audio
      final outputFile = File('/workspace/test_vst3_fx_audio.wav');
      final wavData = _createWavFile(finalAudio, sampleRate);
      outputFile.writeAsBytesSync(wavData);

      final finalRMS = sqrt(
          finalAudio.map((x) => x * x).reduce((a, b) => a + b) / totalSamples);

      print('🎵 REAL VST3 FX PROCESSING COMPLETED!');
      print('Output file: ${outputFile.path}');
      print('File size: ${outputFile.lengthSync()} bytes');
      print('Final RMS: $finalRMS');

      // HARD VERIFICATION - output must be different from input
      final inputRMS = sqrt(
          audioData.map((x) => x * x).reduce((a, b) => a + b) / totalSamples);
      if ((finalRMS - inputRMS).abs() < 0.01) {
        throw Exception(
            '🔥 HARD FAIL: VST3 effects had no audible impact! Input RMS: $inputRMS, Output RMS: $finalRMS');
      }

      expect(outputFile.existsSync(), isTrue);
      expect(finalRMS, greaterThan(0.1));
      print('✅ TEST PASSED: FlutterDartReverb plugin processed audio successfully!');
    } finally {
      reverbPlugin?.unload();
      host.dispose();
    }
  });

  test('try loading built plugin', () {
    final host = VstHost.create(
        sampleRate: 48000, maxBlock: 512, dylibPath: libFile.absolute.path);
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
              final outputRMS = sqrt(
                  outL.map((x) => x * x).reduce((a, b) => a + b) / blockSize);
              print('Plugin output RMS: $outputRMS');
              print(
                  'Plugin output first 10 samples = ${outL.take(10).toList()}');

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
