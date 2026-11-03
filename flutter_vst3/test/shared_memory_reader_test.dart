import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/shared_memory_reader.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';

void main() {
  test('reader invalidation and bounded sample counts', () {
    final memory = calloc<Uint8>(vst3ShmTotalSize);
    addTearDown(() => calloc.free(memory));
    memory.cast<Uint32>().value = vst3ShmMagic;
    final reader = Vst3AudioBufferReader.fromAddress(memory.address)!;
    expect(reader.isValid, isTrue);
    final count =
        Pointer<Int32>.fromAddress(memory.address + vst3OffsetNumSamples);
    count.value = 0x7fffffff;
    expect(reader.numSamples, vst3ShmMaxSamples);
    expect(reader.getOutputL().length, vst3ShmMaxSamples);
    expect(reader.getOutputR().length, vst3ShmMaxSamples);
    expect(reader.getInputL().length, vst3ShmMaxSamples);
    expect(reader.getInputR().length, vst3ShmMaxSamples);
    expect(reader.getLatestOutputSamples(maxCount: 100000).length,
        vst3ShmMaxSamples);
    count.value = -1;
    expect(reader.numSamples, 0);
    expect(reader.getLatestOutputSamples(), isEmpty);
    memory.cast<Uint32>().value = 0;
    expect(reader.isValid, isFalse);
    expect(reader.getOutputL(), isEmpty);
    expect(Vst3AudioBufferReader.fromAddress(0), isNull);
  });
}
