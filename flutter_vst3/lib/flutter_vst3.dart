/// flutter_vst3 - Framework for VST® 3 Plugin Development
///
/// This package provides the complete framework for building VST® 3 plugins
/// with Flutter UI and pure Dart audio processing. It bridges Dart/Flutter
/// code with the Steinberg VST® 3 SDK C++ infrastructure.
///
/// VST® is a trademark of Steinberg Media Technologies GmbH.
library flutter_vst3;

export 'src/vst3_shared_memory_processor.dart' show runVst3SharedMemoryProcessor;
export 'src/vst3_shm_layout.dart';
export 'src/vst3_worker_loop.dart' show Vst3WorkerProcessor;
