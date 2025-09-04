/// Parameter binding between Flutter UI and VST3 audio processor
/// This runs in the SAME isolate as the audio processing
library;

import 'dart:ffi';
import 'dart:typed_data';

/// FFI bindings to C++ parameter bridge
class _ParameterBridgeFFI {
  static final DynamicLibrary _lib = DynamicLibrary.process();
  
  static final void Function(int) _init = _lib
      .lookup<NativeFunction<Void Function(Int32)>>('vst3_parameter_bridge_init')
      .asFunction();
  
  static final void Function(int, double) _setFromUI = _lib
      .lookup<NativeFunction<Void Function(Int32, Double)>>('vst3_parameter_set_from_ui')
      .asFunction();
  
  static final double Function(int) _getForAudio = _lib
      .lookup<NativeFunction<Double Function(Int32)>>('vst3_parameter_get_for_audio')
      .asFunction();
  
  static final bool Function(int) _hasChanged = _lib
      .lookup<NativeFunction<Bool Function(Int32)>>('vst3_parameter_has_changed')
      .asFunction();
  
  static void init(int paramCount) => _init(paramCount);
  static void setFromUI(int id, double value) => _setFromUI(id, value);
  static double getForAudio(int id) => _getForAudio(id);
  static bool hasChanged(int id) => _hasChanged(id);
}

/// Parameter binding for VST3 plugins with Flutter UI
/// This class manages bidirectional parameter updates between
/// the Flutter UI and the VST3 audio processor in the SAME process
class VST3ParameterBinding {
  static VST3ParameterBinding? _instance;
  final List<void Function()> _listeners = [];
  
  final Map<int, double> _parameters = {};
  final Map<int, String> _parameterNames = {};
  final Map<int, String> _parameterUnits = {};
  final int parameterCount;
  
  /// Get singleton instance
  static VST3ParameterBinding getInstance({int paramCount = 0}) {
    _instance ??= VST3ParameterBinding._(paramCount);
    return _instance!;
  }
  
  VST3ParameterBinding._(this.parameterCount) {
    // Initialize FFI bridge
    _ParameterBridgeFFI.init(parameterCount);
    
    // Initialize default values
    for (int i = 0; i < parameterCount; i++) {
      _parameters[i] = 0.0;
    }
  }
  
  /// Add listener for parameter changes
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }
  
  /// Remove listener
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
  
  /// Notify all listeners of parameter changes
  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
  
  /// Get parameter value
  double getParameter(int id) {
    return _parameters[id] ?? 0.0;
  }
  
  /// Set parameter from UI
  /// This directly updates the shared memory in the SAME process
  void setParameter(int id, double value) {
    if (id < 0 || id >= parameterCount) return;
    
    // Clamp value
    value = value.clamp(0.0, 1.0);
    
    // Update local state
    _parameters[id] = value;
    
    // Update shared memory via FFI (SAME PROCESS!)
    _ParameterBridgeFFI.setFromUI(id, value);
    
    // Notify UI listeners
    notifyListeners();
  }
  
  /// Set parameter name
  void setParameterName(int id, String name) {
    _parameterNames[id] = name;
  }
  
  /// Get parameter name
  String getParameterName(int id) {
    return _parameterNames[id] ?? 'Parameter $id';
  }
  
  /// Set parameter units
  void setParameterUnits(int id, String units) {
    _parameterUnits[id] = units;
  }
  
  /// Get parameter units
  String getParameterUnits(int id) {
    return _parameterUnits[id] ?? '';
  }
  
  /// Batch update all parameters
  void setAllParameters(Map<int, double> values) {
    _parameters.clear();
    _parameters.addAll(values);
    
    // Update shared memory for all parameters
    values.forEach((id, value) {
      _ParameterBridgeFFI.setFromUI(id, value);
    });
    
    // Notify UI
    notifyListeners();
  }
  
  /// Get all parameters
  Map<int, double> getAllParameters() {
    return Map.from(_parameters);
  }
}

/// Audio processor base class that uses shared parameters
/// This runs in the SAME isolate as the UI!
abstract class VST3AudioProcessor {
  VST3AudioProcessor();
  
  /// Get parameter value for audio processing
  /// This reads from shared memory in SAME process - no IPC!
  @pragma('vm:prefer-inline')
  double getParameter(int id) {
    return _ParameterBridgeFFI.getForAudio(id);
  }
  
  /// Check if parameter changed
  @pragma('vm:prefer-inline')
  bool hasParameterChanged(int id) {
    return _ParameterBridgeFFI.hasChanged(id);
  }
  
  /// Process audio - to be implemented by plugin
  /// This is called via FFI from the audio thread
  @pragma('vm:entry-point')
  void processAudio(
    Float32List inputL,
    Float32List inputR,
    Float32List outputL,
    Float32List outputR,
    int sampleFrames,
  );
  
  /// Initialize processor
  @pragma('vm:entry-point')
  void initialize(double sampleRate, int maxBlockSize);
  
  /// Reset processor state
  @pragma('vm:entry-point')
  void reset();
}