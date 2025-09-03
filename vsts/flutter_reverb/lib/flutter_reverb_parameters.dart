/// Reverb parameters for the VST3 plugin
class ReverbParameters {
  static const int kRoomSizeParam = 0;
  static const int kDampingParam = 1;
  static const int kWetLevelParam = 2;
  static const int kDryLevelParam = 3;

  /// Controls the size of the reverb space (0% = small room, 100% = large hall)
  double roomSize = 0.5;
  
  /// Controls high frequency absorption (0% = bright, 100% = dark) 
  double damping = 0.5;
  
  /// Controls the level of reverb signal mixed with the input
  double wetLevel = 0.3;
  
  /// Controls the level of direct (unprocessed) signal
  double dryLevel = 0.7;

  /// Get parameter value by ID
  double getParameter(int paramId) {
    return switch (paramId) {
      kRoomSizeParam => roomSize,
      kDampingParam => damping,
      kWetLevelParam => wetLevel,
      kDryLevelParam => dryLevel,
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Set parameter value by ID
  void setParameter(int paramId, double value) {
    final clampedValue = value.clamp(0.0, 1.0);
    switch (paramId) {
      case kRoomSizeParam:
        roomSize = clampedValue;
        break;
      case kDampingParam:
        damping = clampedValue;
        break;
      case kWetLevelParam:
        wetLevel = clampedValue;
        break;
      case kDryLevelParam:
        dryLevel = clampedValue;
        break;
      default:
        throw ArgumentError('Unknown parameter ID: $paramId');
    }
  }

  /// Get parameter name by ID
  String getParameterName(int paramId) {
    return switch (paramId) {
      kRoomSizeParam => 'Room Size',
      kDampingParam => 'Damping',
      kWetLevelParam => 'Wet Level',
      kDryLevelParam => 'Dry Level',
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Get parameter units by ID
  String getParameterUnits(int paramId) {
    return switch (paramId) {
      kRoomSizeParam => '%',
      kDampingParam => '%',
      kWetLevelParam => '%',
      kDryLevelParam => '%',
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Get number of parameters
  static const int numParameters = 4;
}