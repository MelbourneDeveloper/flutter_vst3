import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';
import 'package:flutter_vst3/src/vst3_worker_loop.dart';

void main() {
  test('header magic, version and block bounds are checked', () {
    final memory = calloc<Uint8>(vst3ShmTotalSize);
    final ptr = memory.cast<Void>();
    try {
      expect(() => validateShmHeader(ptr), throwsStateError);
      Pointer<Uint32>.fromAddress(ptr.address + vst3OffsetMagic).value = vst3ShmMagic;
      expect(() => validateShmHeader(ptr), throwsStateError);
      Pointer<Uint32>.fromAddress(ptr.address + vst3OffsetVersion).value = vst3ShmVersion;
      validateShmHeader(ptr);
      final length = Pointer<Int32>.fromAddress(ptr.address + vst3OffsetNumSamples);
      for (final invalid in [-1, vst3ShmMaxSamples + 1]) {
        length.value = invalid;
        expect(() => blockLength(ptr), throwsStateError);
      }
      for (final valid in [0, vst3ShmMaxSamples]) {
        length.value = valid;
        expect(blockLength(ptr), valid);
      }
    } finally {
      calloc.free(memory);
    }
  });
}
