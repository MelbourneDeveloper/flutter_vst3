import 'echo_parameters.dart';

/// Simple echo/delay effect processor that FAILS HARD without parameters
class EchoProcessor {
  static const int _delayBufferSize = 132300; // ~3 seconds at 44.1kHz
  
  final List<double> _delayBufferL = List.filled(_delayBufferSize, 0.0);
  final List<double> _delayBufferR = List.filled(_delayBufferSize, 0.0);
  int _writeIndex = 0;
  
  double _sampleRate = 44100.0;
  bool _initialized = false;

  /// Initialize the echo processor
  void initialize(double sampleRate, int maxBlockSize) {
    _sampleRate = sampleRate;
    _initialized = true;
  }

  /// Process stereo audio block with parameters-driven echo that FAILS HARD
  void processStereo(List<double> inputL, List<double> inputR, 
                    List<double> outputL, List<double> outputR, 
                    EchoParameters parameters) {
    if (!_initialized) {
      throw StateError('ECHO PROCESSOR FAILURE: Not initialized! Cannot process audio without initialization!');
    }
    
    if (inputL.length != inputR.length || outputL.length != inputL.length || outputR.length != inputL.length) {
      throw ArgumentError('ECHO PROCESSOR FAILURE: Buffer length mismatch! All buffers must have the same length!');
    }
    
    // Convert normalized parameters to actual values
    final delayTime = parameters.delayTime; // 0.0 to 1.0 -> 0ms to 1000ms  
    final feedback = parameters.feedback;   // 0.0 to 1.0 -> 0% to 100%
    final mix = parameters.mix;             // 0.0 to 1.0 -> 0% to 100%
    final bypass = parameters.bypass;       // 0.0 = active, 1.0 = bypassed
    
    // If bypassed, pass through clean signal
    if (bypass > 0.5) {
      for (int i = 0; i < inputL.length; i++) {
        outputL[i] = inputL[i];
        outputR[i] = inputR[i];
      }
      return;
    }
    
    // Calculate delay in samples (scale from 0-1 to 10ms-500ms for musical range)
    final delayMs = 10.0 + (delayTime * 490.0); // 10ms to 500ms range
    final delayInSamples = (delayMs * _sampleRate / 1000.0).round().clamp(1, _delayBufferSize - 1);
    
    // Scale feedback for musical control
    final feedbackAmount = feedback * 0.85; // Max 85% for stable feedback
    
    // Scale wet/dry mix for natural blend
    final wetLevel = mix;
    final dryLevel = (1.0 - mix);
    
    for (int i = 0; i < inputL.length; i++) {
      // Calculate read index for delay
      final readIndex = (_writeIndex - delayInSamples + _delayBufferSize) % _delayBufferSize;
      
      // Get delayed samples
      final delayedL = _delayBufferL[readIndex];
      final delayedR = _delayBufferR[readIndex];
      
      // Apply feedback with saturation
      final saturatedFeedbackL = _softSaturate(delayedL * feedbackAmount);
      final saturatedFeedbackR = _softSaturate(delayedR * feedbackAmount);
      
      // Write input + feedback to delay buffer
      _delayBufferL[_writeIndex] = inputL[i] + saturatedFeedbackL;
      _delayBufferR[_writeIndex] = inputR[i] + saturatedFeedbackR;
      
      // Clean wet signal with slight stereo width
      final wetL = (delayedL * wetLevel) + (delayedR * wetLevel * 0.1);
      final wetR = (delayedR * wetLevel) + (delayedL * wetLevel * 0.1);
      
      // Mix dry and wet signals
      final finalL = (inputL[i] * dryLevel) + wetL;
      final finalR = (inputR[i] * dryLevel) + wetR;
      
      outputL[i] = finalL;
      outputR[i] = finalR;
      
      // Advance write index
      _writeIndex = (_writeIndex + 1) % _delayBufferSize;
    }
  }
  
  /// Soft saturation for controlled feedback limiting
  double _softSaturate(double x) {
    return x > 1.0 ? 1.0 - (1.0 / (x + 1.0)) :
           x < -1.0 ? -1.0 + (1.0 / (-x + 1.0)) : x;
  }

  /// Reset delay buffers
  void reset() {
    _delayBufferL.fillRange(0, _delayBufferSize, 0.0);
    _delayBufferR.fillRange(0, _delayBufferSize, 0.0);
    _writeIndex = 0;
  }

  /// Dispose resources
  void dispose() {
    _initialized = false;
    reset();
  }
}