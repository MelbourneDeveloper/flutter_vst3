import 'echo_processor.dart';
import 'echo_parameters.dart';

/// Simple Echo Plugin with natural delay effect and FAIL HARD validation
class DartEchoPlugin {
  
  EchoProcessor? _processor;
  final EchoParameters _parameters = EchoParameters();
  bool _isActive = false;

  /// Initialize the plugin
  bool initialize() {
    _processor = EchoProcessor();
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

  /// Get plugin information from metadata JSON
  Map<String, dynamic> get pluginInfo {
    return {
      'name': 'Echo',
      'vendor': 'CF',
      'version': '1.0.0',
      'category': 'Fx|Delay',
      'type': 'effect',
      'inputs': 2,
      'outputs': 2,
      'parameters': 4,
      'canProcessReplacing': true,
      'hasEditor': false,
    };
  }

  /// Set parameter value by index
  void setParameter(int index, double value) {
    switch (index) {
      case 0:
        _parameters.delayTime = value;
        break;
      case 1:
        _parameters.feedback = value;
        break;
      case 2:
        _parameters.mix = value;
        break;
      case 3:
        _parameters.bypass = value;
        break;
    }
  }

  /// Get parameter value by index
  double getParameter(int index) {
    return switch (index) {
      0 => _parameters.delayTime,
      1 => _parameters.feedback,
      2 => _parameters.mix,
      3 => _parameters.bypass,
      _ => 0.0,
    };
  }

  /// Get parameter info by index
  Map<String, dynamic> getParameterInfo(int index) {
    return switch (index) {
      0 => {
        'name': 'delayTime',
        'displayName': 'Delay Time',
        'description': 'Controls the delay time in milliseconds (0ms to 500ms)',
        'defaultValue': 0.5,
        'units': 'ms',
      },
      1 => {
        'name': 'feedback',
        'displayName': 'Feedback',
        'description': 'Controls the feedback amount (0% = single echo, 85% = max stable)',
        'defaultValue': 0.3,
        'units': '%',
      },
      2 => {
        'name': 'mix',
        'displayName': 'Mix',
        'description': 'Controls the wet/dry mix (0% = dry only, 100% = wet only)',
        'defaultValue': 0.5,
        'units': '%',
      },
      3 => {
        'name': 'bypass',
        'displayName': 'Bypass',
        'description': 'Bypasses the echo effect when enabled',
        'defaultValue': 0.0,
        'units': '',
      },
      _ => {},
    };
  }

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

    // Process the audio through the echo effect with parameters
    if (_processor == null) {
      throw StateError('CRITICAL PLUGIN FAILURE: EchoProcessor not initialized!');
    }
    
    // Use current parameter values (not hardcoded defaults)
    
    _processor!.processStereo(inputL, inputR, outputL, outputR, _parameters);
  }

  /// Dispose resources
  void dispose() {
    _isActive = false;
    _processor?.dispose();
  }
}

/// Factory for creating echo plugin instances
class DartEchoFactory {
  /// Create a new plugin instance
  static DartEchoPlugin createInstance() {
    return DartEchoPlugin();
  }

  /// Get plugin class information from metadata JSON
  static Map<String, dynamic> getClassInfo() {
    return {
      'name': 'Echo',
      'vendor': 'CF',
      'version': '1.0.0',
      'category': 'Fx|Delay',
      'classId': 'DartEcho',
      'controllerId': 'DartEchoController',
    };
  }
}