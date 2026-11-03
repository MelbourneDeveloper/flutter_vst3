import 'package:flutter_vst3/flutter_vst3.dart';
import 'src/reverb_processor.dart';

/// Entry point for the Flutter Reverb processor standalone executable.
///
/// Uses preallocated zero-copy shared memory and POSIX semaphores to receive
/// audio buffers and parameter changes directly from the C++ VST3 plugin wrapper.
void main(List<String> args) {
  runVst3SharedMemoryProcessor(
    args: args,
    processor: ReverbProcessor(),
  );
}