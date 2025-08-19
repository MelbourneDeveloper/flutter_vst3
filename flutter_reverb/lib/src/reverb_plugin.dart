import 'reverb_processor.dart';
import 'reverb_parameters.dart';

/// Unified Dart Reverb Plugin combining VST and VST3 functionality
class DartReverbPlugin {
  static const String pluginName = 'Flutter Dart Reverb';
  static const String vendor = 'Dart Audio';
  static const String version = '1.0.0';
  static const String category = 'Effect';
  
  ReverbProcessor? _processor;
  bool _isActive = false;

  /// Initialize the plugin
  bool initialize() {
    _processor = ReverbProcessor();
    return true;
  }

  /// Set up audio processing parameters
  void setupProcessing(double sampleRate, int maxBlockSize) {
    _processor?.initialize(sampleRate, maxBlockSize);
  }

  /// Activate/deactivate the plugin
  void setActive(bool active) {
    if (active && !_isActive) {
      _processor?.reset();
    }
    _isActive = active;
  }

  /// Set parameter value
  void setParameter(int paramId, double value) {
    _processor?.setParameter(paramId, value);
  }

  /// Get parameter value
  double getParameter(int paramId) {
    return _processor?.getParameter(paramId) ?? 0.0;
  }

  /// Get parameter info
  ParameterInfo getParameterInfo(int paramId) {
    if (paramId >= ReverbParameters.numParameters) {
      throw ArgumentError('Invalid parameter ID: $paramId');
    }

    return ParameterInfo(
      id: paramId,
      name: ReverbParameters().getParameterName(paramId),
      shortName: ReverbParameters().getParameterName(paramId),
      units: ReverbParameters().getParameterUnits(paramId),
      minValue: 0.0,
      maxValue: 1.0,
      defaultValue: _getDefaultValue(paramId),
      canAutomate: true,
    );
  }

  double _getDefaultValue(int paramId) {
    return switch (paramId) {
      ReverbParameters.kRoomSizeParam => 0.5,
      ReverbParameters.kDampingParam => 0.5,
      ReverbParameters.kWetLevelParam => 0.3,
      ReverbParameters.kDryLevelParam => 0.7,
      _ => 0.0,
    };
  }

  /// Get number of parameters
  int get parameterCount => ReverbParameters.numParameters;

  /// Process audio block
  void processAudio(List<List<double>> inputs, List<List<double>> outputs) {
    if (!_isActive || inputs.isEmpty || outputs.isEmpty) {
      return;
    }

    // Ensure we have stereo inputs and outputs
    final inputL = inputs.isNotEmpty ? inputs[0] : <double>[];
    final inputR = inputs.length > 1 ? inputs[1] : inputL;
    
    if (outputs.isEmpty) return;
    final outputL = outputs[0];
    final outputR = outputs.length > 1 ? outputs[1] : outputL;

    if (inputL.isEmpty || outputL.isEmpty) return;

    // Process the audio through the reverb
    _processor?.processStereo(inputL, inputR, outputL, outputR);
  }

  /// Get plugin information
  Map<String, dynamic> get pluginInfo {
    return {
      'name': pluginName,
      'vendor': vendor,
      'version': version,
      'category': category,
      'type': 'effect',
      'inputs': 2,
      'outputs': 2,
      'parameters': parameterCount,
      'canProcessReplacing': true,
      'hasEditor': true,
    };
  }

  /// Save plugin state
  Map<String, dynamic> saveState() {
    final state = <String, dynamic>{};
    for (int i = 0; i < parameterCount; i++) {
      state['param_$i'] = getParameter(i);
    }
    state['version'] = version;
    return state;
  }

  /// Load plugin state
  void loadState(Map<String, dynamic> state) {
    for (int i = 0; i < parameterCount; i++) {
      final key = 'param_$i';
      if (state.containsKey(key)) {
        setParameter(i, (state[key] as num).toDouble());
      }
    }
  }

  /// Dispose resources
  void dispose() {
    _isActive = false;
    _processor?.dispose();
  }
}

/// Parameter information class
class ParameterInfo {
  final int id;
  final String name;
  final String shortName;
  final String units;
  final double minValue;
  final double maxValue;
  final double defaultValue;
  final bool canAutomate;

  const ParameterInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.units,
    required this.minValue,
    required this.maxValue,
    required this.defaultValue,
    required this.canAutomate,
  });
}

/// Factory for creating plugin instances
class DartReverbFactory {
  /// Create a new plugin instance
  static DartReverbPlugin createInstance() {
    return DartReverbPlugin();
  }

  /// Get plugin class information
  static Map<String, dynamic> getClassInfo() {
    return {
      'name': DartReverbPlugin.pluginName,
      'vendor': DartReverbPlugin.vendor,
      'version': DartReverbPlugin.version,
      'category': DartReverbPlugin.category,
      'classId': 'FlutterDartReverb',
      'controllerId': 'FlutterDartReverbController',
    };
  }
}