/// Dart VST3 Bridge - FFI Interface for VST3 Plugin Development
/// 
/// This package provides the FFI bridge between pure Dart audio processing
/// code and the VST3 SDK C++ infrastructure. Any Dart VST3 plugin should
/// use this package to register callbacks and communicate with the host.
library dart_vst3_bridge;

export 'src/vst3_bridge.dart';
export 'src/vst3_callbacks.dart';
export 'src/vst3_parameters.dart';