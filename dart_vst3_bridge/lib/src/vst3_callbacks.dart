import 'dart:ffi' as ffi;
import 'vst3_bridge.dart';

/// C function type definitions for FFI callbacks
typedef InitializeProcessorC = ffi.Void Function(ffi.Double sampleRate, ffi.Int32 maxBlockSize);
typedef InitializeProcessorDart = void Function(double sampleRate, int maxBlockSize);

typedef ProcessAudioC = ffi.Void Function(ffi.Pointer<ffi.Float> inputL, 
                                         ffi.Pointer<ffi.Float> inputR,
                                         ffi.Pointer<ffi.Float> outputL, 
                                         ffi.Pointer<ffi.Float> outputR,
                                         ffi.Int32 numSamples);
typedef ProcessAudioDart = void Function(ffi.Pointer<ffi.Float> inputL, 
                                        ffi.Pointer<ffi.Float> inputR,
                                        ffi.Pointer<ffi.Float> outputL, 
                                        ffi.Pointer<ffi.Float> outputR,
                                        int numSamples);

typedef SetParameterC = ffi.Void Function(ffi.Int32 paramId, ffi.Double normalizedValue);
typedef SetParameterDart = void Function(int paramId, double normalizedValue);

typedef GetParameterC = ffi.Double Function(ffi.Int32 paramId);
typedef GetParameterDart = double Function(int paramId);

typedef GetParameterCountC = ffi.Int32 Function();
typedef GetParameterCountDart = int Function();

typedef ResetC = ffi.Void Function();
typedef ResetDart = void Function();

/// Register Dart callbacks with C++ layer
/// This must be called before the VST3 plugin can use the Dart processor
void registerVST3Callbacks() {
  // Export Dart functions as C callbacks
  final initCallback = ffi.Pointer.fromFunction<InitializeProcessorC>(
    VST3Bridge.initializeProcessor);
  final processCallback = ffi.Pointer.fromFunction<ProcessAudioC>(
    VST3Bridge.processAudio);
  final setParamCallback = ffi.Pointer.fromFunction<SetParameterC>(
    VST3Bridge.setParameter);
  final getParamCallback = ffi.Pointer.fromFunction<GetParameterC>(
    VST3Bridge.getParameter, 0.0);
  final getParamCountCallback = ffi.Pointer.fromFunction<GetParameterCountC>(
    VST3Bridge.getParameterCount, 0);
  final resetCallback = ffi.Pointer.fromFunction<ResetC>(
    VST3Bridge.reset);

  // Register callbacks with C++ (requires C++ function to accept callbacks)
  // This would be implemented in the C++ VST3 wrapper
  // dvh_register_dart_callbacks(initCallback, processCallback, setParamCallback, etc.)
}