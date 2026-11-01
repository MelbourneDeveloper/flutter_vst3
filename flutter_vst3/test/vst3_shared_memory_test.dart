import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_vst3/flutter_vst3.dart';
import 'package:test/test.dart';

final class _MockProcessor {
  bool initialized = false;
  double sampleRate = 0.0;
  int maxBlockSize = 0;

  void initialize(double sr, int bs) {
    initialized = true;
    sampleRate = sr;
    maxBlockSize = bs;
  }

  void processStereo(List<double> inL, List<double> inR, List<double> outL, List<double> outR) {}
  void setParameter(int paramId, double value) {}
  void dispose() => initialized = false;
}

void main() {
  test('runVst3SharedMemoryProcessor throws when args are empty', () {
    expect(
      () => runVst3SharedMemoryProcessor(
        args: [],
        processor: _MockProcessor(),
      ),
      throwsArgumentError,
    );
  });

  test('runVst3SharedMemoryProcessor throws when args are incomplete', () {
    expect(
      () => runVst3SharedMemoryProcessor(
        args: ['/shm_name', '/sem_ready'],
        processor: _MockProcessor(),
      ),
      throwsArgumentError,
    );
  });

  test('runVst3SharedMemoryProcessor validates magic number', () {
    final lib = DynamicLibrary.process();
    final shmOpen = lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32, Uint16), int Function(Pointer<Utf8>, int, int)>('shm_open');
    final ftruncate = lib.lookupFunction<Int32 Function(Int32, Int64), int Function(int, int)>('ftruncate');
    final mmap = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, Int64), Pointer<Void> Function(Pointer<Void>, int, int, int, int, int)>('mmap');
    final shmUnlink = lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('shm_unlink');
    final semOpen = lib.lookupFunction<Pointer<Void> Function(Pointer<Utf8>, Int32, Uint16, Uint32), Pointer<Void> Function(Pointer<Utf8>, int, int, int)>('sem_open');
    final semUnlink = lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('sem_unlink');
    final semClose = lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('sem_close');

    final shmName = '/test_magic_shm'.toNativeUtf8();
    final semRName = '/test_magic_r'.toNativeUtf8();
    final semDName = '/test_magic_d'.toNativeUtf8();

    shmUnlink(shmName);
    semUnlink(semRName);
    semUnlink(semDName);

    final fd = shmOpen(shmName, 0x0200 | 2, 438); // O_CREAT | O_RDWR, 0666
    ftruncate(fd, 69632);
    final ptr = mmap(nullptr, 69632, 3, 1, fd, 0);
    // Write INVALID magic number
    ptr.cast<Uint32>().value = 0x12345678;

    semClose(semOpen(semRName, 0x0200, 438, 0));
    semClose(semOpen(semDName, 0x0200, 438, 0));

    expect(
      () => runVst3SharedMemoryProcessor(
        args: ['/test_magic_shm', '/test_magic_r', '/test_magic_d'],
        processor: _MockProcessor(),
      ),
      throwsStateError,
    );

    shmUnlink(shmName);
    semUnlink(semRName);
    semUnlink(semDName);
    calloc.free(shmName);
    calloc.free(semRName);
    calloc.free(semDName);
  });
}
