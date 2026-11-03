// Copyright (c) 2025
// Direct read access to VST3 zero-copy shared memory audio buffers.

import 'dart:ffi';
import 'dart:typed_data';

import 'vst3_shm_layout.dart';

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
      : _outputL =
            Pointer<Float>.fromAddress(_base.address + vst3OffsetOutputL),
        _outputR =
            Pointer<Float>.fromAddress(_base.address + vst3OffsetOutputR),
        _inputL = Pointer<Float>.fromAddress(_base.address + vst3OffsetInputL),
        _inputR = Pointer<Float>.fromAddress(_base.address + vst3OffsetInputR),
        _numSamplesPtr =
            Pointer<Int32>.fromAddress(_base.address + vst3OffsetNumSamples),
        _sampleRatePtr =
            Pointer<Double>.fromAddress(_base.address + vst3OffsetSampleRate);

  /// Attaches directly to a shared memory block using an in-process raw address.
  static Vst3AudioBufferReader? fromAddress(int address) {
    if (address == 0) return null;
    final ptr = Pointer<Uint8>.fromAddress(address);
    final magic = Pointer<Uint32>.fromAddress(ptr.address).value;
    return (magic == vst3ShmMagic) ? Vst3AudioBufferReader._(ptr) : null;
  }

  /// Checks whether the underlying shared memory block is still valid and active.
  bool get isValid {
    if (_base == nullptr || _base.address == 0) return false;
    final magic = Pointer<Uint32>.fromAddress(_base.address).value;
    return magic == vst3ShmMagic;
  }

  /// Raw base memory pointer of the mapped shared memory block.
  Pointer<Uint8> get baseAddress => _base;

  /// Current number of valid samples processed in the active audio block.
  int get numSamples {
    if (!isValid) return 0;
    return _numSamplesPtr.value.clamp(0, vst3ShmMaxSamples);
  }

  /// Host audio sample rate in Hz.
  double get sampleRate {
    return isValid
        ? _sampleRatePtr.value
        : throw StateError('Shared memory reader is no longer valid');
  }

  /// Returns a zero-copy typed list view over the left output channel buffer.
  Float32List getOutputL([int? count]) => _channelView(_outputL, count);

  /// Returns a zero-copy typed list view over the right output channel buffer.
  Float32List getOutputR([int? count]) => _channelView(_outputR, count);

  /// Returns a zero-copy typed list view over the left input channel buffer.
  Float32List getInputL([int? count]) => _channelView(_inputL, count);

  /// Returns a zero-copy typed list view over the right input channel buffer.
  Float32List getInputR([int? count]) => _channelView(_inputR, count);

  /// Channel view for [channel], clamped by [count] and the block maximum,
  /// empty while the block is invalid ([TELEMETRY-BOUNDS]).
  Float32List _channelView(Pointer<Float> channel, int? count) => isValid
      ? channel.asTypedList((count ?? numSamples).clamp(0, vst3ShmMaxSamples))
      : Float32List(0);

  /// Returns a mixed stereo waveform snapshot up to [maxCount] samples.
  Float32List getLatestOutputSamples({int maxCount = 256}) {
    if (!isValid) return Float32List(0);
    final active = numSamples;
    final n = active.clamp(0, maxCount.clamp(0, vst3ShmMaxSamples));
    final out = Float32List(n);
    final lList = _outputL.asTypedList(n);
    final rList = _outputR.asTypedList(n);
    for (var i = 0; i < n; i++) {
      out[i] = (lList[i] + rList[i]) * 0.5;
    }
    return out;
  }
}
