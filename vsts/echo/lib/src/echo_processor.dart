import 'dart:math' as math;
import 'dart:typed_data';
import 'echo_parameters.dart';

/// Simple echo/delay effect processor that FAILS HARD without parameters
class EchoProcessor {
  static const int _delayBufferSize = 132300; // ~3 seconds at 44.1kHz
  
  final Float32List _delayBufferL = Float32List(_delayBufferSize);
  final Float32List _delayBufferR = Float32List(_delayBufferSize);
  int _writeIndex = 0;
  
  double _sampleRate = 44100.0;
  bool _initialized = false;
  double _currentDelaySamples = -1.0;
  double _smoothCoeff = 0.00075;

  /// Initialize the echo processor
  void initialize(double sampleRate, int maxBlockSize) {
    _sampleRate = sampleRate;
    _smoothCoeff = 1.0 - math.exp(-1.0 / (_sampleRate * 0.03));
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

  void _copyBypass(
    Float32List inL,
    Float32List inR,
    Float32List outL,
    Float32List outR,
  ) {
    for (var i = 0; i < inL.length; i++) {
      outL[i] = inL[i];
      outR[i] = inR[i];
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

    final dL = _delayBufferL[i0] + frac * (_delayBufferL[i1] - _delayBufferL[i0]);
    final dR = _delayBufferR[i0] + frac * (_delayBufferR[i1] - _delayBufferR[i0]);
    _delayBufferL[_writeIndex] = inL + _softSaturate(dL * feedbackAmt);
    _delayBufferR[_writeIndex] = inR + _softSaturate(dR * feedbackAmt);
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
    if (parameters.bypass > 0.5) {
      _copyBypass(inputL, inputR, outputL, outputR);
      return;
    }
    
    final delayMs = 10.0 + (parameters.delayTime * 490.0);
    final targetDelay = (delayMs * _sampleRate / 1000.0)
        .clamp(1.0, (_delayBufferSize - 2).toDouble());
    if (_currentDelaySamples < 0) _currentDelaySamples = targetDelay;
    
    final fb = parameters.feedback * 0.85;
    final wet = parameters.mix;
    final dry = 1.0 - parameters.mix;

    for (var i = 0; i < inputL.length; i++) {
      _processSample(inputL[i], inputR[i], targetDelay, fb, wet, dry, outputL, outputR, i);
    }
    _snapshotWaveform(outputL, outputR);
  }

  /// Latest audio output samples shared with the GUI visualizer.
  static final Float32List waveformBuffer = Float32List(256);

  /// Copies downsampled stereo output samples into the waveform buffer.
  void _snapshotWaveform(Float32List outL, Float32List outR) {
    final count = outL.length < 256 ? outL.length : 256;
    for (var i = 0; i < count; i++) {
      waveformBuffer[i] = (outL[i] + outR[i]) * 0.5;
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
    _currentDelaySamples = -1.0;
  }

  /// Dispose resources
  void dispose() {
    _initialized = false;
    reset();
  }
}