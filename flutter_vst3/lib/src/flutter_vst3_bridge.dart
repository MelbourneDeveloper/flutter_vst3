import 'dart:ffi' as ffi;

/// Abstract interface that all Dart VST3 processors must implement
abstract class VST3Processor {
  /// Initialize the processor with sample rate and block size
  void initialize(double sampleRate, int maxBlockSize);

  /// Process stereo audio
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR);

  /// Set parameter value (normalized 0.0-1.0)
  void setParameter(int paramId, double normalizedValue);

  /// Get parameter value (normalized 0.0-1.0)
  double getParameter(int paramId);

  /// Get total number of parameters
  int getParameterCount();

  /// Reset processor state
  void reset();

  /// Dispose resources
  void dispose();
}

/// Callback function signatures for FFI
typedef DartInitializeProcessorNative = ffi.Void Function(ffi.Double, ffi.Int32);
typedef DartProcessAudioNative = ffi.Void Function(ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Int32);
typedef DartSetParameterNative = ffi.Void Function(ffi.Int32, ffi.Double);
typedef DartGetParameterNative = ffi.Double Function(ffi.Int32);
typedef DartGetParameterCountNative = ffi.Int32 Function();
typedef DartResetNative = ffi.Void Function();
typedef DartDisposeNative = ffi.Void Function();

/// Main FFI bridge between Dart VST3 plugins and C++ VST3 infrastructure
class VST3Bridge {
  static VST3Processor? _processor;

  /// Register a Dart VST3 processor with the bridge
  /// This must be called before the VST3 plugin can process audio
  static void registerProcessor(VST3Processor processor) {
    _processor = processor;
    print('Dart VST3 processor registered locally (callbacks not yet implemented in FFI layer)');
  }

  /// Initialize the processor
  /// Called from C++ when VST3 plugin is initialized
  static void initializeProcessor(double sampleRate, int maxBlockSize) {
    if (_processor == null) {
      throw StateError('CRITICAL VST3 BRIDGE FAILURE: Cannot initialize - no processor registered! Call VST3Bridge.registerProcessor() before using the plugin!');
    }
    _processor!.initialize(sampleRate, maxBlockSize);
  }

  /// Process stereo audio block
  /// Called from C++ VST3 processor during audio processing
  static void processAudio(ffi.Pointer<ffi.Float> inputL, 
                          ffi.Pointer<ffi.Float> inputR,
                          ffi.Pointer<ffi.Float> outputL, 
                          ffi.Pointer<ffi.Float> outputR,
                          int numSamples) {
    if (_processor == null) {
      throw StateError('CRITICAL VST3 BRIDGE FAILURE: No processor registered! Audio processing CANNOT continue without a Dart processor! Call VST3Bridge.registerProcessor() first!');
    }

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

    // Process through Dart processor
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
    return _processor?.getParameterCount() ?? 0;
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