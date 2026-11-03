import 'dart:math' as math;
import 'dart:typed_data';
import 'echo_parameters.dart';

/// Simple echo/delay effect processor that FAILS HARD without parameters
class EchoProcessor {
  int _delayBufferSize = 0;
  
  Float32List _delayBufferL = Float32List(0);
  Float32List _delayBufferR = Float32List(0);
  int _writeIndex = 0;
  
  double _sampleRate = 44100.0;
  bool _initialized = false;
  double _currentDelaySamples = -1.0;
  double _smoothCoeff = 0.0;

  /// Initialize the echo processor
  void initialize(double sampleRate, int maxBlockSize) {
    _sampleRate = sampleRate;
    sampleRate.isFinite && sampleRate > 0 && maxBlockSize > 0
        ? null : throw ArgumentError("Invalid audio configuration");
    _smoothCoeff = 1.0 - math.exp(-1.0 / (sampleRate * 0.03));
    _delayBufferSize = sampleRate.ceil() + 2;
    _delayBufferL = Float32List(_delayBufferSize);
    _delayBufferR = Float32List(_delayBufferSize);
    reset();
    _initialized = true;
  }

  void _validateBuffers(
    Float32List inL,
    Float32List inR,
    Float32List outL,
    Float32List outR,
  ) {
    if (!_initialized) {
      throw StateError(
        'ECHO PROCESSOR FAILURE: Not initialized! Cannot process audio without initialization!',
      );
    }
    if (inL.length != inR.length ||
        outL.length != inL.length ||
        outR.length != inL.length) {
      throw ArgumentError(
        'ECHO PROCESSOR FAILURE: Buffer length mismatch! All buffers must have the same length!',
      );
    }
  }

  void _processSample(
    double inL,
    double inR,
    double targetDelay,
    double feedbackAmt,
    double wet,
    double dry,
    Float32List outL,
    Float32List outR,
    int i,
  ) {
    _currentDelaySamples += (targetDelay - _currentDelaySamples) * _smoothCoeff;
    var pos = _writeIndex - _currentDelaySamples;
    if (pos < 0) pos += _delayBufferSize;
    final i0 = pos.toInt();
    final frac = pos - i0;
    final i1 = i0 + 1 >= _delayBufferSize ? 0 : i0 + 1;

    // Under one sample of delay there is nothing older to read but the input.
    final dL = _currentDelaySamples < 1.0 ? inL : _delayBufferL[i0] + frac * (_delayBufferL[i1] - _delayBufferL[i0]);
    final dR = _currentDelaySamples < 1.0 ? inR : _delayBufferR[i0] + frac * (_delayBufferR[i1] - _delayBufferR[i0]);
    _delayBufferL[_writeIndex] = inL + softSaturate(dL * feedbackAmt);
    _delayBufferR[_writeIndex] = inR + softSaturate(dR * feedbackAmt);
    outL[i] = (inL * dry) + (dL * wet) + (dR * wet * 0.1);
    outR[i] = (inR * dry) + (dR * wet) + (dL * wet * 0.1);
    _writeIndex = (_writeIndex + 1) % _delayBufferSize;
  }

  /// Process stereo audio block with parameters-driven echo that FAILS HARD
  void processStereo(
    Float32List inputL,
    Float32List inputR, 
    Float32List outputL,
    Float32List outputR, 
    EchoParameters parameters,
  ) {
    _validateBuffers(inputL, inputR, outputL, outputR);
    final targetDelay = parameters.delayTime.clamp(0.0, 1.0) * _sampleRate;
    _currentDelaySamples = _currentDelaySamples < 0 ? targetDelay : _currentDelaySamples;
    final fb = parameters.feedback * 0.85;
    final wet = parameters.bypass > 0.5 ? 0.0 : parameters.mix;
    final dry = 1.0 - wet;

    for (var i = 0; i < inputL.length; i++) {
      _processSample(inputL[i], inputR[i], targetDelay, fb, wet, dry, outputL, outputR, i);
    }

  }

  /// Unity gain up to a magnitude of 1, then a limit approaching 2. Value and
  /// slope are both continuous at the threshold.
  static double softSaturate(double x) => x > 1.0
      ? 2.0 - 1.0 / x
      : x < -1.0
          ? -2.0 - 1.0 / x
          : x;

  /// Reset delay buffers
  void reset() {
    _delayBufferL.fillRange(0, _delayBufferSize, 0.0);
    _delayBufferR.fillRange(0, _delayBufferSize, 0.0);
    _writeIndex = 0;
    _currentDelaySamples = -1.0;
  }

  /// Dispose resources
  void dispose() {
    _initialized = false;
    reset();
  }
}