// Worker used by ipc_host_test.cpp. It's a real compiled Dart worker with DSP
// whose behaviour the native test controls and inspects through parameters.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_vst3/flutter_vst3.dart';

const int _paramStallMs = 0;
const int _paramExit = 1;
const int _paramThrow = 2;
const int _paramProbe = 3;
const int _paramValue = 4;

const int _probeSampleRate = 1;
const int _probeMaxBlock = 2;
const int _probeBlocks = 3;
const int _probeResets = 4;
const int _probeLastValue = 5;
const int _probeInitializes = 6;

/// Output left is the input plus a running total of samples, so that any stale
/// or repeated block is visible. Output right reports the selected probe.
final class _ProbeProcessor implements Vst3WorkerProcessor {
  double _sampleRate = 0;
  int _maxBlock = 0;
  int _blocks = 0;
  int _resets = 0;
  int _initializes = 0;
  double _lastValue = -1;
  int _stallMs = 0;
  int _probe = 0;

  @override
  void initialize(double sampleRate, int maxBlockSize) {
    _sampleRate = sampleRate;
    _maxBlock = maxBlockSize;
    _initializes++;
  }

  @override
  void setParameter(int paramId, double value) {
    switch (paramId) {
      case _paramStallMs:
        _stallMs = value.toInt();
      case _paramExit:
        value > 0 ? exit(3) : null;
      case _paramThrow:
        value > 0 ? throw StateError('Probe DSP failure') : null;
      case _paramProbe:
        _probe = value.toInt();
      case _paramValue:
        _lastValue = value;
    }
  }

  double get _probeValue => switch (_probe) {
        _probeSampleRate => _sampleRate,
        _probeMaxBlock => _maxBlock.toDouble(),
        _probeBlocks => _blocks.toDouble(),
        _probeResets => _resets.toDouble(),
        _probeLastValue => _lastValue,
        _probeInitializes => _initializes.toDouble(),
        _ => 0,
      };

  @override
  void processStereo(
    Float32List inputL,
    Float32List inputR,
    Float32List outputL,
    Float32List outputR,
  ) {
    _blocks++;
    _stallMs > 0 ? sleep(Duration(milliseconds: _stallMs)) : null;
    _stallMs = 0;
    final probe = _probeValue;
    for (var i = 0; i < inputL.length; i++) {
      outputL[i] = inputL[i] * 2;
      outputR[i] = probe;
    }
  }

  @override
  void reset() => _resets++;

  @override
  void dispose() {}
}

void main(List<String> args) {
  runVst3SharedMemoryProcessor(args: args, processor: _ProbeProcessor());
}
