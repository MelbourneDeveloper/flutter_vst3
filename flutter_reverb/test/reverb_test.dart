import 'dart:math' as math;
import '../lib/src/reverb_plugin.dart';
import '../lib/src/reverb_parameters.dart';
import '../lib/src/reverb_processor.dart';

/// Comprehensive test suite for the unified Flutter Reverb package
void main() {
  print('=== Flutter Reverb Test Suite ===\n');
  
  _testReverbParameters();
  _testReverbProcessor();
  _testReverbPlugin();
  _testIntegration();
  
  print('🎉 All tests passed! Flutter Reverb package is working correctly.');
}

void _testReverbParameters() {
  print('Testing ReverbParameters...');
  
  final params = ReverbParameters();
  
  // Test default values
  assert(params.roomSize == 0.5, 'Default room size should be 0.5');
  assert(params.damping == 0.5, 'Default damping should be 0.5');
  assert(params.wetLevel == 0.3, 'Default wet level should be 0.3');
  assert(params.dryLevel == 0.7, 'Default dry level should be 0.7');
  
  // Test parameter setting and getting
  params.setParameter(ReverbParameters.kRoomSizeParam, 0.8);
  assert(params.getParameter(ReverbParameters.kRoomSizeParam) == 0.8, 'Room size should be 0.8');
  
  // Test clamping
  params.setParameter(ReverbParameters.kWetLevelParam, 1.5);
  assert(params.getParameter(ReverbParameters.kWetLevelParam) == 1.0, 'Wet level should be clamped to 1.0');
  
  params.setParameter(ReverbParameters.kDryLevelParam, -0.5);
  assert(params.getParameter(ReverbParameters.kDryLevelParam) == 0.0, 'Dry level should be clamped to 0.0');
  
  // Test parameter names
  assert(params.getParameterName(ReverbParameters.kRoomSizeParam) == 'Room Size', 'Room size name should match');
  assert(params.getParameterName(ReverbParameters.kDampingParam) == 'Damping', 'Damping name should match');
  
  // Test parameter units
  assert(params.getParameterUnits(ReverbParameters.kWetLevelParam) == '%', 'Wet level units should be %');
  
  print('✓ ReverbParameters tests passed\n');
}

void _testReverbProcessor() {
  print('Testing ReverbProcessor...');
  
  final processor = ReverbProcessor();
  processor.initialize(44100.0, 512);
  
  // Test parameter setting
  processor.setParameter(ReverbParameters.kRoomSizeParam, 0.7);
  assert(processor.getParameter(ReverbParameters.kRoomSizeParam) == 0.7, 'Processor should store parameter values');
  
  // Test audio processing
  const numSamples = 100;
  final inputL = List.generate(numSamples, (i) => math.sin(i * 0.1) * 0.5);
  final inputR = List.generate(numSamples, (i) => math.sin(i * 0.1) * 0.5);
  final outputL = List<double>.filled(numSamples, 0.0);
  final outputR = List<double>.filled(numSamples, 0.0);
  
  processor.processStereo(inputL, inputR, outputL, outputR);
  
  // Verify output is not just zeros
  final hasNonZero = outputL.any((sample) => sample.abs() > 0.001);
  assert(hasNonZero, 'Processor should produce non-zero output');
  
  // Test reset
  processor.reset();
  
  // Test disposal
  processor.dispose();
  
  print('✓ ReverbProcessor tests passed\n');
}

void _testReverbPlugin() {
  print('Testing DartReverbPlugin...');
  
  final plugin = DartReverbPlugin();
  assert(plugin.initialize(), 'Plugin should initialize successfully');
  
  plugin.setupProcessing(44100.0, 512);
  plugin.setActive(true);
  
  // Test parameter count
  assert(plugin.parameterCount == 4, 'Plugin should have 4 parameters');
  
  // Test parameter info
  final paramInfo = plugin.getParameterInfo(ReverbParameters.kRoomSizeParam);
  assert(paramInfo.name == 'Room Size', 'Parameter info name should match');
  assert(paramInfo.units == '%', 'Parameter info units should match');
  assert(paramInfo.canAutomate, 'Parameters should be automatable');
  
  // Test plugin info
  final pluginInfo = plugin.pluginInfo;
  assert(pluginInfo['name'] == 'Flutter Dart Reverb', 'Plugin name should match');
  assert(pluginInfo['vendor'] == 'Dart Audio', 'Plugin vendor should match');
  assert(pluginInfo['inputs'] == 2, 'Plugin should have 2 inputs');
  assert(pluginInfo['outputs'] == 2, 'Plugin should have 2 outputs');
  
  // Test audio processing
  const numSamples = 50;
  final inputL = List.generate(numSamples, (i) => math.sin(i * 0.2) * 0.3);
  final inputR = List.generate(numSamples, (i) => math.sin(i * 0.2) * 0.3);
  final outputL = List<double>.filled(numSamples, 0.0);
  final outputR = List<double>.filled(numSamples, 0.0);
  
  plugin.processAudio([inputL, inputR], [outputL, outputR]);
  
  // Verify processing worked
  final processedSamples = outputL.where((sample) => sample.abs() > 0.001).length;
  assert(processedSamples > 0, 'Plugin should process audio samples');
  
  // Test state management
  plugin.setParameter(ReverbParameters.kRoomSizeParam, 0.9);
  final state = plugin.saveState();
  assert(state['param_0'] == 0.9, 'State should contain parameter value');
  
  plugin.setParameter(ReverbParameters.kRoomSizeParam, 0.1);
  plugin.loadState(state);
  assert(plugin.getParameter(ReverbParameters.kRoomSizeParam) == 0.9, 'State should be restored');
  
  plugin.setActive(false);
  plugin.dispose();
  
  print('✓ DartReverbPlugin tests passed\n');
}

void _testIntegration() {
  print('Testing integration scenarios...');
  
  // Test multiple plugin instances
  final plugin1 = DartReverbPlugin();
  final plugin2 = DartReverbPlugin();
  
  assert(plugin1.initialize(), 'First plugin should initialize');
  assert(plugin2.initialize(), 'Second plugin should initialize');
  
  plugin1.setupProcessing(44100.0, 256);
  plugin2.setupProcessing(48000.0, 1024);
  
  plugin1.setActive(true);
  plugin2.setActive(true);
  
  // Set different parameters
  plugin1.setParameter(ReverbParameters.kRoomSizeParam, 0.3);
  plugin2.setParameter(ReverbParameters.kRoomSizeParam, 0.8);
  
  assert(plugin1.getParameter(ReverbParameters.kRoomSizeParam) == 0.3, 'Plugin instances should be independent');
  assert(plugin2.getParameter(ReverbParameters.kRoomSizeParam) == 0.8, 'Plugin instances should be independent');
  
  // Process audio on both
  const numSamples = 32;
  final input = List.generate(numSamples, (i) => math.sin(i * 0.3) * 0.4);
  final output1 = List<double>.filled(numSamples, 0.0);
  final output2 = List<double>.filled(numSamples, 0.0);
  
  plugin1.processAudio([input, input], [output1, List<double>.filled(numSamples, 0.0)]);
  plugin2.processAudio([input, input], [output2, List<double>.filled(numSamples, 0.0)]);
  
  // Outputs should be different due to different parameters
  bool outputsDiffer = false;
  for (int i = 0; i < numSamples; i++) {
    if ((output1[i] - output2[i]).abs() > 0.001) {
      outputsDiffer = true;
      break;
    }
  }
  assert(outputsDiffer, 'Different plugin settings should produce different outputs');
  
  plugin1.dispose();
  plugin2.dispose();
  
  print('✓ Integration tests passed\n');
}