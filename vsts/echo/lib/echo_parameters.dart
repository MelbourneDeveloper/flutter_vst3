/// Echo parameters for the VST3 plugin
class EchoParameters {
  static const int kDelayTimeParam = 0;
  static const int kFeedbackParam = 1;
  static const int kMixParam = 2;
  static const int kBypassParam = 3;

  /// Controls the delay time in milliseconds (0ms to 1000ms)
  double delayTime = 0.5;
  
  /// Controls the feedback amount (0% = single echo, 100% = infinite)
  double feedback = 0.3;
  
  /// Controls the wet/dry mix (0% = dry only, 100% = wet only)
  double mix = 0.5;
  
  /// Bypasses the echo effect when enabled
  double bypass = 0.0;

  /// Get parameter value by ID
  double getParameter(int paramId) {
    return switch (paramId) {
      kDelayTimeParam => delayTime,
      kFeedbackParam => feedback,
      kMixParam => mix,
      kBypassParam => bypass,
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Set parameter value by ID
  void setParameter(int paramId, double value) {
    final clampedValue = value.clamp(0.0, 1.0);
    switch (paramId) {
      case kDelayTimeParam:
        delayTime = clampedValue;
        break;
      case kFeedbackParam:
        feedback = clampedValue;
        break;
      case kMixParam:
        mix = clampedValue;
        break;
      case kBypassParam:
        bypass = clampedValue;
        break;
      default:
        throw ArgumentError('Unknown parameter ID: $paramId');
    }
  }

  /// Get parameter name by ID
  String getParameterName(int paramId) {
    return switch (paramId) {
      kDelayTimeParam => 'Delay Time',
      kFeedbackParam => 'Feedback',
      kMixParam => 'Mix',
      kBypassParam => 'Bypass',
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Get parameter units by ID
  String getParameterUnits(int paramId) {
    return switch (paramId) {
      kDelayTimeParam => 'ms',
      kFeedbackParam => '%',
      kMixParam => '%',
      kBypassParam => '',
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Get number of parameters
  static const int numParameters = 4;
}