// Copyright (c) 2025
// Shared setup for tests that poke VST3 shared-memory blocks directly.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';
import 'package:flutter_vst3/src/vst3_worker_loop.dart';

/// Channel buffer offsets in L-in, R-in, L-out, R-out order
/// ([IPC-BLOCK-OFFSETS]).
const List<int> channelOffsets = [
  vst3OffsetInputL,
  vst3OffsetInputR,
  vst3OffsetOutputL,
  vst3OffsetOutputR,
];

/// Allocates a live [vst3ShmTotalSize] block ([IPC-BLOCK-MAGIC]) that frees
/// itself at test end.
Pointer<Uint8> shmBlock() {
  final memory = calloc<Uint8>(vst3ShmTotalSize);
  addTearDown(() => calloc.free(memory));
  writeU32(memory, vst3OffsetMagic, vst3ShmMagic);
  return memory;
}

/// Marks [memory] live ([IPC-BLOCK-MAGIC]) and expects the header check to
/// keep rejecting the block while the protocol version is missing, then
/// completes the header.
void writeLiveMagicExpectingVersionReject(Pointer<Uint8> memory) {
  writeU32(memory, vst3OffsetMagic, vst3ShmMagic);
  expect(() => validateShmHeader(memory.cast<Void>()), throwsStateError);
  writeU32(memory, vst3OffsetVersion, vst3ShmVersion);
}

/// Writes [value] into the u32 field at [offset].
void writeU32(Pointer<Uint8> memory, int offset, int value) =>
    Pointer<Uint32>.fromAddress(memory.address + offset).value = value;

/// Writes [value] into the i32 field at [offset].
void writeI32(Pointer<Uint8> memory, int offset, int value) =>
    Pointer<Int32>.fromAddress(memory.address + offset).value = value;

/// Writes [value] into the f64 field at [offset].
void writeF64(Pointer<Uint8> memory, int offset, double value) =>
    Pointer<Double>.fromAddress(memory.address + offset).value = value;

/// Reads sample [index] of the f32 channel at [offset].
double readF32(Pointer<Uint8> memory, int offset, int index) =>
    Pointer<Float>.fromAddress(memory.address + offset)[index];

/// Fills all four channel buffers with `channel * [scale] + sample + [base]`.
void fillChannels(
  Pointer<Uint8> memory, {
  required int samples,
  required int scale,
  required double base,
}) {
  for (var channel = 0; channel < channelOffsets.length; channel++) {
    for (var sample = 0; sample < samples; sample++) {
      Pointer<Float>.fromAddress(memory.address + channelOffsets[channel])[
          sample] = channel * scale + sample + base;
    }
  }
}
