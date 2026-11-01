import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';

/// Allocates a zeroed protocol block for reader and widget tests.
Pointer<Uint8> allocateSharedMemoryFixture() => calloc<Uint8>(vst3ShmTotalSize);

/// Releases a block after its readers have been disposed.
void freeSharedMemoryFixture(Pointer<Uint8> memory) => calloc.free(memory);
