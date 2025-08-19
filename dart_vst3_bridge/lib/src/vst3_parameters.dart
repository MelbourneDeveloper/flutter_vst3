/// VST3 Parameter utilities and types
/// 
/// This file provides common parameter handling utilities that Dart VST3
/// plugins can use for consistent parameter management.

/// Common parameter information structure
class VST3ParameterInfo {
  final int id;
  final String name;
  final String shortName;
  final String units;
  final double minValue;
  final double maxValue;
  final double defaultNormalized;
  final bool canAutomate;

  const VST3ParameterInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.units,
    this.minValue = 0.0,
    this.maxValue = 1.0,
    required this.defaultNormalized,
    this.canAutomate = true,
  });
}

/// Base class for parameter management in VST3 plugins
abstract class VST3ParameterHandler {
  /// Get parameter information by index
  VST3ParameterInfo getParameterInfo(int index);

  /// Get total number of parameters
  int get parameterCount;

  /// Convert normalized value (0.0-1.0) to display string
  String parameterToString(int paramId, double normalizedValue);

  /// Convert display string to normalized value (0.0-1.0)
  double stringToParameter(int paramId, String text);

  /// Get default normalized value for parameter
  double getDefaultValue(int paramId);
}