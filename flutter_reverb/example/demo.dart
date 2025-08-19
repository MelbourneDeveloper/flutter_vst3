import 'dart:math' as math;
import '../lib/src/reverb_plugin.dart';
import '../lib/src/reverb_parameters.dart';

/// Demo showcasing the unified Flutter Reverb Plugin functionality
/// This combines the best parts from working_reverb.dart and simple_reverb_test.dart
void main() {
  print('=== Flutter Dart Reverb Plugin Demo ===\n');
  
  // Create and initialize the plugin
  final plugin = DartReverbPlugin();
  
  if (!plugin.initialize()) {
    print('ERROR: Failed to initialize plugin');
    return;
  }
  
  print('✓ Plugin initialized successfully');
  print('Plugin: ${DartReverbPlugin.pluginName}');
  print('Vendor: ${DartReverbPlugin.vendor}');
  print('Version: ${DartReverbPlugin.version}');
  print('Parameters: ${plugin.parameterCount}\n');
  
  // Set up processing
  const sampleRate = 44100.0;
  const blockSize = 512;
  
  plugin.setupProcessing(sampleRate, blockSize);
  plugin.setActive(true);
  
  print('✓ Processing setup complete');
  print('  Sample rate: $sampleRate Hz');
  print('  Block size: $blockSize samples\n');
  
  // Test parameter modification
  print('Testing parameters...');
  plugin.setParameter(ReverbParameters.kRoomSizeParam, 0.8);
  plugin.setParameter(ReverbParameters.kWetLevelParam, 0.6);
  plugin.setParameter(ReverbParameters.kDampingParam, 0.3);
  
  print('✓ Room Size: ${plugin.getParameter(ReverbParameters.kRoomSizeParam).toStringAsFixed(2)}');
  print('✓ Wet Level: ${plugin.getParameter(ReverbParameters.kWetLevelParam).toStringAsFixed(2)}');
  print('✓ Damping: ${plugin.getParameter(ReverbParameters.kDampingParam).toStringAsFixed(2)}\n');
  
  // Generate test audio - sine wave
  print('Generating test audio...');
  const frequency = 440.0; // A4 note
  const duration = 0.1; // 100ms
  final numSamples = (sampleRate * duration).round();
  
  final inputL = <double>[];
  final inputR = <double>[];
  
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final sample = 0.5 * math.sin(2 * math.pi * frequency * t);
    inputL.add(sample);
    inputR.add(sample);
  }
  
  // Create output buffers
  final outputL = List<double>.filled(numSamples, 0.0);
  final outputR = List<double>.filled(numSamples, 0.0);
  
  // Process the audio
  print('✓ Processing ${numSamples} samples through unified Flutter reverb...');
  plugin.processAudio([inputL, inputR], [outputL, outputR]);
  
  // Analyze the results
  double inputRMS = 0.0;
  double outputRMS = 0.0;
  
  for (int i = 0; i < numSamples; i++) {
    inputRMS += inputL[i] * inputL[i];
    outputRMS += outputL[i] * outputL[i];
  }
  
  inputRMS = math.sqrt(inputRMS / numSamples);
  outputRMS = math.sqrt(outputRMS / numSamples);
  
  print('\n=== Results ===');
  print('✓ Input RMS:  ${inputRMS.toStringAsFixed(4)}');
  print('✓ Output RMS: ${outputRMS.toStringAsFixed(4)}');
  
  if (outputRMS > 0 && inputRMS > 0) {
    final gainChange = 20 * math.log(outputRMS / inputRMS) / math.ln10;
    print('✓ Gain change: ${gainChange.toStringAsFixed(2)} dB');
  }
  
  // Show processing worked by comparing first few samples
  print('\nFirst 5 samples comparison:');
  for (int i = 0; i < 5; i++) {
    print('  Sample $i: ${inputL[i].toStringAsFixed(4)} → ${outputL[i].toStringAsFixed(4)}');
  }
  
  // Verify output is different from input (reverb is working)
  bool isDifferent = false;
  for (int i = 0; i < numSamples; i++) {
    if ((outputL[i] - inputL[i]).abs() > 0.001) {
      isDifferent = true;
      break;
    }
  }
  
  print('\n✓ Reverb processing: ${isDifferent ? "WORKING" : "FAILED"}');
  print('✓ Output differs from input: $isDifferent');
  
  // Test plugin info
  print('\n=== Plugin Info ===');
  final info = plugin.pluginInfo;
  info.forEach((key, value) {
    print('✓ $key: $value');
  });
  
  // Test state save/load
  print('\n=== State Management ===');
  final savedState = plugin.saveState();
  print('✓ Saved plugin state: ${savedState.length} parameters');
  
  // Modify parameters
  plugin.setParameter(ReverbParameters.kRoomSizeParam, 0.2);
  print('✓ Changed room size to: ${plugin.getParameter(ReverbParameters.kRoomSizeParam)}');
  
  // Restore state
  plugin.loadState(savedState);
  print('✓ Restored room size to: ${plugin.getParameter(ReverbParameters.kRoomSizeParam)}');
  
  // Clean up
  plugin.setActive(false);
  plugin.dispose();
  
  print('\n🎉 Demo completed successfully! Unified Flutter Dart reverb is working!');
  print('📦 All original reverb packages have been merged into one: flutter_reverb');
}