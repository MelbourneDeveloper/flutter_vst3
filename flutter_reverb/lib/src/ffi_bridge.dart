import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'reverb_processor.dart';

/// FFI bridge between Dart reverb processor and C++ VST3 infrastructure
class ReverbFFIBridge {
  static final _dylib = _loadLibrary();
  static ReverbProcessor? _processor;
  
  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libdart_vst_host.dylib');
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libdart_vst_host.so');
    } else if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('dart_vst_host.dll');
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Initialize the Dart reverb processor
  /// Called from C++ when VST3 plugin is initialized
  static void initializeProcessor(double sampleRate, int maxBlockSize) {
    _processor = ReverbProcessor();
    _processor!.initialize(sampleRate, maxBlockSize);
  }

  /// Process stereo audio block
  /// Called from C++ VST3 processor during audio processing
  static void processAudio(ffi.Pointer<ffi.Float> inputL, 
                          ffi.Pointer<ffi.Float> inputR,
                          ffi.Pointer<ffi.Float> outputL, 
                          ffi.Pointer<ffi.Float> outputR,
                          int numSamples) {
    if (_processor == null) return;

    // Convert C pointers to Dart lists
    final inL = inputL.asTypedList(numSamples);
    final inR = inputR.asTypedList(numSamples);
    final outL = outputL.asTypedList(numSamples);
    final outR = outputR.asTypedList(numSamples);

    // Convert float arrays to double arrays for Dart processing
    final dartInL = List<double>.generate(numSamples, (i) => inL[i].toDouble());
    final dartInR = List<double>.generate(numSamples, (i) => inR[i].toDouble());
    final dartOutL = List<double>.filled(numSamples, 0.0);
    final dartOutR = List<double>.filled(numSamples, 0.0);

    // Process through Dart reverb
    _processor!.processStereo(dartInL, dartInR, dartOutL, dartOutR);

    // Convert back to C float arrays
    for (int i = 0; i < numSamples; i++) {
      outL[i] = dartOutL[i];
      outR[i] = dartOutR[i];
    }
  }

  /// Set parameter value
  /// Called from C++ when VST3 parameter changes
  static void setParameter(int paramId, double normalizedValue) {
    _processor?.setParameter(paramId, normalizedValue);
  }

  /// Get parameter value
  /// Called from C++ when VST3 needs current parameter value
  static double getParameter(int paramId) {
    return _processor?.getParameter(paramId) ?? 0.0;
  }

  /// Get parameter count
  static int getParameterCount() {
    return 4; // room_size, damping, wet_level, dry_level
  }

  /// Reset processor state
  /// Called from C++ when VST3 is activated/deactivated
  static void reset() {
    _processor?.reset();
  }

  /// Dispose resources
  static void dispose() {
    _processor?.dispose();
    _processor = null;
  }
}

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
void registerDartCallbacks() {
  // Export Dart functions as C callbacks
  final initCallback = ffi.Pointer.fromFunction<InitializeProcessorC>(
    ReverbFFIBridge.initializeProcessor);
  final processCallback = ffi.Pointer.fromFunction<ProcessAudioC>(
    ReverbFFIBridge.processAudio);
  final setParamCallback = ffi.Pointer.fromFunction<SetParameterC>(
    ReverbFFIBridge.setParameter);
  final getParamCallback = ffi.Pointer.fromFunction<GetParameterC>(
    ReverbFFIBridge.getParameter, 0.0);
  final getParamCountCallback = ffi.Pointer.fromFunction<GetParameterCountC>(
    ReverbFFIBridge.getParameterCount, 0);
  final resetCallback = ffi.Pointer.fromFunction<ResetC>(
    ReverbFFIBridge.reset);

  // Register callbacks with C++ (requires C++ function to accept callbacks)
  // This would be implemented in the C++ VST3 wrapper
  // dvh_register_dart_callbacks(initCallback, processCallback, setParamCallback, etc.)
}