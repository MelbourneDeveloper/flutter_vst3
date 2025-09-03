import 'dart:math' as math;
import '../lib/flutter_reverb_parameters.dart';
import '../lib/src/reverb_processor.dart';

/// Test suite for Flutter Reverb VST3 plugin components
void main() {
  print('=== Flutter Reverb Test Suite ===\n');
  
  _testReverbParameters();
  _testReverbProcessor();
  
  print('🎉 All tests passed! Flutter Reverb components are working correctly.');
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
  
  // Test parameter constants
  assert(ReverbParameters.kRoomSizeParam == 0, 'Room size param ID should be 0');
  assert(ReverbParameters.kDampingParam == 1, 'Damping param ID should be 1');
  assert(ReverbParameters.kWetLevelParam == 2, 'Wet level param ID should be 2');
  assert(ReverbParameters.kDryLevelParam == 3, 'Dry level param ID should be 3');
  assert(ReverbParameters.numParameters == 4, 'Should have 4 parameters');
  
  print('✓ ReverbParameters tests passed\n');
}

void _testReverbProcessor() {
  print('Testing ReverbProcessor...');
  
  final processor = ReverbProcessor();
  processor.initialize(44100.0, 512);
  
  // Test parameter setting
  processor.setParameter(ReverbParameters.kRoomSizeParam, 0.7);
  assert(processor.getParameter(ReverbParameters.kRoomSizeParam) == 0.7, 'Processor should store parameter values');
  
  // Test different parameter values
  processor.setParameter(ReverbParameters.kDampingParam, 0.9);
  processor.setParameter(ReverbParameters.kWetLevelParam, 0.4);
  processor.setParameter(ReverbParameters.kDryLevelParam, 0.6);
  
  assert(processor.getParameter(ReverbParameters.kDampingParam) == 0.9, 'Damping should be set');
  assert(processor.getParameter(ReverbParameters.kWetLevelParam) == 0.4, 'Wet level should be set');
  assert(processor.getParameter(ReverbParameters.kDryLevelParam) == 0.6, 'Dry level should be set');
  
  // Test audio processing
  const numSamples = 100;
  final inputL = List.generate(numSamples, (i) => math.sin(i * 0.1) * 0.5);
  final inputR = List.generate(numSamples, (i) => math.cos(i * 0.1) * 0.5);
  final outputL = List<double>.filled(numSamples, 0.0);
  final outputR = List<double>.filled(numSamples, 0.0);
  
  processor.processStereo(inputL, inputR, outputL, outputR);
  
  // Verify output is not just zeros (reverb should produce some output)
  final hasNonZeroL = outputL.any((sample) => sample.abs() > 0.001);
  final hasNonZeroR = outputR.any((sample) => sample.abs() > 0.001);
  assert(hasNonZeroL, 'Processor should produce non-zero left output');
  assert(hasNonZeroR, 'Processor should produce non-zero right output');
  
  // Test silence processing (should still work)
  final silentL = List<double>.filled(numSamples, 0.0);
  final silentR = List<double>.filled(numSamples, 0.0);
  final outputSilentL = List<double>.filled(numSamples, 0.0);
  final outputSilentR = List<double>.filled(numSamples, 0.0);
  
  processor.processStereo(silentL, silentR, outputSilentL, outputSilentR);
  // With silence, output should be very quiet but might not be exactly zero due to reverb tail
  
  // Test reset
  processor.reset();
  
  // Test disposal
  processor.dispose();
  
  print('✓ ReverbProcessor tests passed\n');
}