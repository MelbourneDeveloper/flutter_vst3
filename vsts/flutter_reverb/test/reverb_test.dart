import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_reverb/flutter_reverb_parameters.dart';
import 'package:flutter_reverb/src/reverb_processor.dart';

/// Test suite for Flutter Reverb VST3 plugin components
void main() {
  test('invalid buffers throw and reset clears tail', () {
    final dsp = ReverbProcessor();
    final zero = Float32List(4096);
    final output = Float32List(4096);
    expect(() => dsp.processStereo(zero, zero, output, output), throwsStateError);
    dsp.initialize(44100, 4096);
    expect(() => dsp.processStereo(zero, Float32List(1), output, output), throwsStateError);
    final impulse = Float32List(4096)..[0] = 1;
    dsp.processStereo(impulse, impulse, output, Float32List(4096));
    expect(output.any((x) => x != 0), isTrue);
    dsp.reset();
    dsp.processStereo(zero, zero, output, Float32List(4096));
    expect(output, everyElement(0));
  });
  test('parameters' , _testReverbParameters);
  test('processor', _testReverbProcessor);
}

void _testReverbParameters() {
  
  final params = ReverbParameters();
  
  // Test default values
  expect(params.roomSize == 0.5, isTrue, reason: 'Default room size should be 0.5');
  expect(params.damping == 0.5, isTrue, reason: 'Default damping should be 0.5');
  expect(params.wetLevel == 0.3, isTrue, reason: 'Default wet level should be 0.3');
  expect(params.dryLevel == 0.7, isTrue, reason: 'Default dry level should be 0.7');
  
  // Test parameter setting and getting
  params.setParameter(ReverbParameters.kRoomSizeParam, 0.8);
  expect(params.getParameter(ReverbParameters.kRoomSizeParam) == 0.8, isTrue, reason: 'Room size should be 0.8');
  
  // Test clamping
  params.setParameter(ReverbParameters.kWetLevelParam, 1.5);
  expect(params.getParameter(ReverbParameters.kWetLevelParam) == 1.0, isTrue, reason: 'Wet level should be clamped to 1.0');
  
  params.setParameter(ReverbParameters.kDryLevelParam, -0.5);
  expect(params.getParameter(ReverbParameters.kDryLevelParam) == 0.0, isTrue, reason: 'Dry level should be clamped to 0.0');
  
  // Test parameter names
  expect(params.getParameterName(ReverbParameters.kRoomSizeParam) == 'Room Size', isTrue, reason: 'Room size name should match');
  expect(params.getParameterName(ReverbParameters.kDampingParam) == 'Damping', isTrue, reason: 'Damping name should match');
  
  // Test parameter units
  expect(params.getParameterUnits(ReverbParameters.kWetLevelParam) == '%', isTrue, reason: 'Wet level units should be %');
  
  // Test parameter constants
  expect(ReverbParameters.kRoomSizeParam == 0, isTrue, reason: 'Room size param ID should be 0');
  expect(ReverbParameters.kDampingParam == 1, isTrue, reason: 'Damping param ID should be 1');
  expect(ReverbParameters.kWetLevelParam == 2, isTrue, reason: 'Wet level param ID should be 2');
  expect(ReverbParameters.kDryLevelParam == 3, isTrue, reason: 'Dry level param ID should be 3');
  expect(ReverbParameters.numParameters == 4, isTrue, reason: 'Should have 4 parameters');
  
}

void _testReverbProcessor() {
  
  final processor = ReverbProcessor();
  processor.initialize(44100.0, 512);
  
  // Test parameter setting
  processor.setParameter(ReverbParameters.kRoomSizeParam, 0.7);
  expect(processor.getParameter(ReverbParameters.kRoomSizeParam) == 0.7, isTrue, reason: 'Processor should store parameter values');
  
  // Test different parameter values
  processor.setParameter(ReverbParameters.kDampingParam, 0.9);
  processor.setParameter(ReverbParameters.kWetLevelParam, 0.4);
  processor.setParameter(ReverbParameters.kDryLevelParam, 0.6);
  
  expect(processor.getParameter(ReverbParameters.kDampingParam) == 0.9, isTrue, reason: 'Damping should be set');
  expect(processor.getParameter(ReverbParameters.kWetLevelParam) == 0.4, isTrue, reason: 'Wet level should be set');
  expect(processor.getParameter(ReverbParameters.kDryLevelParam) == 0.6, isTrue, reason: 'Dry level should be set');
  
  // Test audio processing
  const numSamples = 100;
  final inputL = Float32List.fromList(List.generate(numSamples, (i) => math.sin(i * 0.1) * 0.5));
  final inputR = Float32List.fromList(List.generate(numSamples, (i) => math.cos(i * 0.1) * 0.5));
  final outputL = Float32List(numSamples);
  final outputR = Float32List(numSamples);
  
  processor.processStereo(inputL, inputR, outputL, outputR);
  
  // Verify output is not just zeros (reverb should produce some output)
  final hasNonZeroL = outputL.any((sample) => sample.abs() > 0.001);
  final hasNonZeroR = outputR.any((sample) => sample.abs() > 0.001);
  expect(hasNonZeroL, isTrue, reason: 'Processor should produce non-zero left output');
  expect(hasNonZeroR, isTrue, reason: 'Processor should produce non-zero right output');
  
  // Test silence processing (should still work)
  final silentL = Float32List(numSamples);
  final silentR = Float32List(numSamples);
  final outputSilentL = Float32List(numSamples);
  final outputSilentR = Float32List(numSamples);
  
  processor.processStereo(silentL, silentR, outputSilentL, outputSilentR);
  // With silence, output should be very quiet but might not be exactly zero due to reverb tail
  
  // Test reset
  processor.reset();
  
  // Test disposal
  processor.dispose();
  
}