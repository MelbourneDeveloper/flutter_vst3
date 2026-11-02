import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/shared_memory_reader.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';

Pointer<Uint8> _memory() {
  final memory = calloc<Uint8>(vst3ShmTotalSize);
  addTearDown(() => calloc.free(memory));
  memory.cast<Uint32>().value = vst3ShmMagic;
  Pointer<Int32>.fromAddress(memory.address + vst3OffsetNumSamples).value = 3;
  final offsets = [vst3OffsetInputL, vst3OffsetInputR,
    vst3OffsetOutputL, vst3OffsetOutputR];
  for (var channel = 0; channel < 4; channel++) {
    final raw = Pointer<Float>.fromAddress(memory.address + offsets[channel]);
    for (var sample = 0; sample < 3; sample++) {
      raw[sample] = channel * 10 + sample + 0.5;
    }
  }
  return memory;
}

void main() {
  test('reader routes four distinct channels and averages exactly', () {
    final memory = _memory();
    final reader = Vst3AudioBufferReader.fromAddress(memory.address)!;
    expect(reader.getInputL(), [0.5, 1.5, 2.5]);
    expect(reader.getInputR(), [10.5, 11.5, 12.5]);
    expect(reader.getOutputL(), [20.5, 21.5, 22.5]);
    expect(reader.getOutputR(), [30.5, 31.5, 32.5]);
    expect(reader.getLatestOutputSamples(), [25.5, 26.5, 27.5]);
    expect(reader.getLatestOutputSamples(maxCount: 2), [25.5, 26.5]);
    reader.getInputL()[1] = -7;
    expect(Pointer<Float>.fromAddress(memory.address + vst3OffsetInputL)[1], -7);
  });
}
