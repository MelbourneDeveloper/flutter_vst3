import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'flutter_vst3_bridge.dart';

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

typedef DisposeC = ffi.Void Function();
typedef DisposeDart = void Function();

// C++ function bindings
typedef CreateInstanceC = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);
typedef CreateInstanceDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>);

typedef RegisterCallbacksC = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<DartVST3Callbacks>);
typedef RegisterCallbacksDart = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<DartVST3Callbacks>);

// Struct matching the C++ DartVST3Callbacks structure
final class DartVST3Callbacks extends ffi.Struct {
  external ffi.Pointer<ffi.NativeFunction<InitializeProcessorC>> initializeProcessor;
  external ffi.Pointer<ffi.NativeFunction<ProcessAudioC>> processAudio;
  external ffi.Pointer<ffi.NativeFunction<SetParameterC>> setParameter;
  external ffi.Pointer<ffi.NativeFunction<GetParameterC>> getParameter;
  external ffi.Pointer<ffi.NativeFunction<GetParameterCountC>> getParameterCount;
  external ffi.Pointer<ffi.NativeFunction<ResetC>> reset;
  external ffi.Pointer<ffi.NativeFunction<DisposeC>> dispose;
}

/// Register Dart callbacks with C++ layer
/// This MUST be called before the VST3 plugin can use the Dart processor
void registerVST3Callbacks({required String pluginId}) {
  try {
    // Load the native library
    late ffi.DynamicLibrary lib;
    if (Platform.isMacOS) {
      lib = ffi.DynamicLibrary.open('libdart_vst_host.dylib');
    } else if (Platform.isLinux) {
      lib = ffi.DynamicLibrary.open('libdart_vst_host.so');
    } else if (Platform.isWindows) {
      lib = ffi.DynamicLibrary.open('dart_vst_host.dll');
    } else {
      throw UnsupportedError('Unsupported platform for VST3 callbacks');
    }

    // Get C++ function pointers
    final createInstance = lib.lookupFunction<CreateInstanceC, CreateInstanceDart>(
      'dart_vst3_create_instance');
    final registerCallbacks = lib.lookupFunction<RegisterCallbacksC, RegisterCallbacksDart>(
      'dart_vst3_register_callbacks');

    // Create plugin instance
    final pluginIdPtr = pluginId.toNativeUtf8();
    final instance = createInstance(pluginIdPtr);
    
    if (instance == ffi.nullptr) {
      throw StateError('CRITICAL VST3 BRIDGE FAILURE: Failed to create plugin instance for $pluginId');
    }

    // Create callback structure and populate with Dart function pointers
    final callbacks = calloc<DartVST3Callbacks>();
    callbacks.ref.initializeProcessor = ffi.Pointer.fromFunction<InitializeProcessorC>(
      VST3Bridge.initializeProcessor);
    callbacks.ref.processAudio = ffi.Pointer.fromFunction<ProcessAudioC>(
      VST3Bridge.processAudio);
    callbacks.ref.setParameter = ffi.Pointer.fromFunction<SetParameterC>(
      VST3Bridge.setParameter);
    callbacks.ref.getParameter = ffi.Pointer.fromFunction<GetParameterC>(
      VST3Bridge.getParameter, 0.0);
    callbacks.ref.getParameterCount = ffi.Pointer.fromFunction<GetParameterCountC>(
      VST3Bridge.getParameterCount, 0);
    callbacks.ref.reset = ffi.Pointer.fromFunction<ResetC>(
      VST3Bridge.reset);
    callbacks.ref.dispose = ffi.Pointer.fromFunction<DisposeC>(
      VST3Bridge.dispose);

    // Register callbacks with C++ bridge
    final result = registerCallbacks(instance, callbacks);
    
    if (result == 0) {
      calloc.free(callbacks);
      throw StateError('CRITICAL VST3 BRIDGE FAILURE: Failed to register callbacks for $pluginId');
    }

    // Cleanup
    calloc.free(callbacks);
    print('VST3 callbacks successfully registered for $pluginId');
    
  } catch (e, stackTrace) {
    print('FATAL VST3 BRIDGE ERROR: Failed to register callbacks for $pluginId');
    print('Error: $e');
    print('Stack trace: $stackTrace');
    throw StateError('VST3 bridge initialization failed: $e');
  }
}