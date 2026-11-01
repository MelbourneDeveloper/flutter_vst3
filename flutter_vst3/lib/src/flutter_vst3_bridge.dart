import 'dart:typed_data';

/// Abstract interface that all Dart VST3 processors must implement
abstract class VST3Processor {
  /// Initialize the processor with sample rate and block size
  void initialize(double sampleRate, int maxBlockSize);

  /// Process stereo audio
  void processStereo(Float32List inputL, Float32List inputR,
      Float32List outputL, Float32List outputR);

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
