// Copyright (c) 2025
// Direct read access to VST3 zero-copy shared memory audio buffers.

import 'dart:ffi';
import 'dart:typed_data';

/// Magic constant identifying valid VST3 shared memory ('VST3').
const int _vst3Magic = 0x56535433;

/// Memory byte offsets matching the C++ Vst3SharedMemory structure.
const int _offsetSampleRate = 8;
const int _offsetNumSamples = 24;
const int _offsetInputL = 4096;
const int _offsetInputR = 20480;
const int _offsetOutputL = 36864;
const int _offsetOutputR = 53248;
const int _maxSamples = 4096;

/// Reader providing direct zero-copy read access to VST3 audio buffers.
final class Vst3AudioBufferReader {
  final Pointer<Uint8> _base;
  final Pointer<Float> _outputL;
  final Pointer<Float> _outputR;
  final Pointer<Float> _inputL;
  final Pointer<Float> _inputR;
  final Pointer<Int32> _numSamplesPtr;
  final Pointer<Double> _sampleRatePtr;

  Vst3AudioBufferReader._(this._base)
      : _outputL = Pointer<Float>.fromAddress(_base.address + _offsetOutputL),
        _outputR = Pointer<Float>.fromAddress(_base.address + _offsetOutputR),
        _inputL = Pointer<Float>.fromAddress(_base.address + _offsetInputL),
        _inputR = Pointer<Float>.fromAddress(_base.address + _offsetInputR),
        _numSamplesPtr = Pointer<Int32>.fromAddress(_base.address + _offsetNumSamples),
        _sampleRatePtr = Pointer<Double>.fromAddress(_base.address + _offsetSampleRate);

  /// Attaches directly to a shared memory block using an in-process raw address.
  static Vst3AudioBufferReader? fromAddress(int address) {
    if (address == 0) return null;
    final ptr = Pointer<Uint8>.fromAddress(address);
    final magic = Pointer<Uint32>.fromAddress(ptr.address).value;
    return (magic == _vst3Magic) ? Vst3AudioBufferReader._(ptr) : null;
  }

  /// Checks whether the underlying shared memory block is still valid and active.
  bool get isValid {
    if (_base == nullptr || _base.address == 0) return false;
    try {
      final magic = Pointer<Uint32>.fromAddress(_base.address).value;
      return magic == _vst3Magic;
    } catch (_) {
      return false;
    }
  }

  /// Raw base memory pointer of the mapped shared memory block.
  Pointer<Uint8> get baseAddress => _base;

  /// Current number of valid samples processed in the active audio block.
  int get numSamples {
    if (!isValid) return 0;
    try {
      return _numSamplesPtr.value.clamp(0, _maxSamples);
    } catch (_) {
      return 0;
    }
  }

  /// Host audio sample rate in Hz.
  double get sampleRate {
    if (!isValid) return 44100.0;
    try {
      return _sampleRatePtr.value;
    } catch (_) {
      return 44100.0;
    }
  }

  /// Returns a zero-copy typed list view over the left output channel buffer.
  Float32List getOutputL([int? count]) {
    if (!isValid) return Float32List(0);
    try {
      final n = (count ?? numSamples).clamp(0, _maxSamples);
      return _outputL.asTypedList(n);
    } catch (_) {
      return Float32List(0);
    }
  }

  /// Returns a zero-copy typed list view over the right output channel buffer.
  Float32List getOutputR([int? count]) {
    if (!isValid) return Float32List(0);
    try {
      final n = (count ?? numSamples).clamp(0, _maxSamples);
      return _outputR.asTypedList(n);
    } catch (_) {
      return Float32List(0);
    }
  }

  /// Returns a zero-copy typed list view over the left input channel buffer.
  Float32List getInputL([int? count]) {
    if (!isValid) return Float32List(0);
    try {
      final n = (count ?? numSamples).clamp(0, _maxSamples);
      return _inputL.asTypedList(n);
    } catch (_) {
      return Float32List(0);
    }
  }

  /// Returns a zero-copy typed list view over the right input channel buffer.
  Float32List getInputR([int? count]) {
    if (!isValid) return Float32List(0);
    try {
      final n = (count ?? numSamples).clamp(0, _maxSamples);
      return _inputR.asTypedList(n);
    } catch (_) {
      return Float32List(0);
    }
  }

  /// Returns a mixed stereo waveform snapshot up to [maxCount] samples.
  Float32List getLatestOutputSamples({int maxCount = 256}) {
    if (!isValid) return Float32List(0);
    try {
      final active = numSamples;
      final n = (active == 0 ? maxCount : active).clamp(1, maxCount);
      final out = Float32List(n);
      final lList = _outputL.asTypedList(n);
      final rList = _outputR.asTypedList(n);
      for (var i = 0; i < n; i++) {
        out[i] = (lList[i] + rList[i]) * 0.5;
      }
      return out;
    } catch (_) {
      return Float32List(0);
    }
  }
}
