import 'dart:typed_data';
import 'package:flutter_vst3/flutter_vst3.dart';
import 'src/echo_parameters.dart';
import 'src/echo_processor.dart';

/// Adapts the Echo DSP engine and parameter state to match the interface
/// expected by [runVst3SharedMemoryProcessor].
final class _EchoProcessorWrapper implements Vst3WorkerProcessor {
  final EchoProcessor _processor = EchoProcessor();
  final EchoParameters _parameters = EchoParameters();

  @override
  void initialize(double sampleRate, int maxBlockSize) =>
      _processor.initialize(sampleRate, maxBlockSize);

  @override
  void setParameter(int paramId, double value) =>
      _parameters.setParameter(paramId, value);

  @override
  void processStereo(
    Float32List inputL,
    Float32List inputR,
    Float32List outputL,
    Float32List outputR,
  ) =>
      _processor.processStereo(inputL, inputR, outputL, outputR, _parameters);

  @override
  void reset() => _processor.reset();

  @override
  void dispose() => _processor.dispose();
}


/// Entry point for Echo processor executable.
/// Uses preallocated zero-copy shared memory and POSIX semaphores.
void main(List<String> args) {
  runVst3SharedMemoryProcessor(
    args: args,
    processor: _EchoProcessorWrapper(),
  );
}
