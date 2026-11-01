import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Magic constant identifying valid VST3 shared memory ('VST3').
const int _vst3ShmMagic = 0x56535433;

/// Command from host to process an audio block.
const int _vst3CmdProcess = 1;

/// Command from host requesting the DSP process to terminate cleanly.
const int _vst3CmdTerminate = 2;

// Memory byte offsets matching the C++ Vst3SharedMemory struct definition
const int _offsetMagic = 0;
const int _offsetSampleRate = 8;
const int _offsetMaxBlockSize = 16;
const int _offsetCommand = 20;
const int _offsetNumSamples = 24;
const int _offsetHostParamWrite = 28;
const int _offsetHostParamRead = 32;
const int _offsetHostParams = 36;
const int _offsetInputL = 4096;
const int _offsetInputR = 20480;
const int _offsetOutputL = 36864;
const int _offsetOutputR = 53248;
const int _vst3ShmTotalSize = 69632;

// C and Dart function signatures for POSIX shared memory and semaphores
typedef _ShmOpenC = Int32 Function(Pointer<Utf8>, Int32, Uint16);
typedef _ShmOpenDart = int Function(Pointer<Utf8>, int, int);
typedef _MmapC = Pointer<Void> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, Int64);
typedef _MmapDart = Pointer<Void> Function(Pointer<Void>, int, int, int, int, int);
typedef _MunmapC = Int32 Function(Pointer<Void>, IntPtr);
typedef _MunmapDart = int Function(Pointer<Void>, int);
typedef _CloseC = Int32 Function(Int32);
typedef _CloseDart = int Function(int);
typedef _SemOpenC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _SemOpenDart = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _SemWaitC = Int32 Function(Pointer<Void>);
typedef _SemWaitDart = int Function(Pointer<Void>);
typedef _SemPostC = Int32 Function(Pointer<Void>);
typedef _SemPostDart = int Function(Pointer<Void>);
typedef _SemCloseC = Int32 Function(Pointer<Void>);
typedef _SemCloseDart = int Function(Pointer<Void>);

/// POSIX FFI bindings for inter-process shared memory and semaphores.
final class _PosixNative {
  final _ShmOpenDart shmOpen;
  final _MmapDart mmap;
  final _MunmapDart munmap;
  final _CloseDart close;
  final _SemOpenDart semOpen;
  final _SemWaitDart semWait;
  final _SemPostDart semPost;
  final _SemCloseDart semClose;

  _PosixNative(DynamicLibrary lib)
      : shmOpen = lib.lookupFunction<_ShmOpenC, _ShmOpenDart>('shm_open'),
        mmap = lib.lookupFunction<_MmapC, _MmapDart>('mmap'),
        munmap = lib.lookupFunction<_MunmapC, _MunmapDart>('munmap'),
        close = lib.lookupFunction<_CloseC, _CloseDart>('close'),
        semOpen = lib.lookupFunction<_SemOpenC, _SemOpenDart>('sem_open'),
        semWait = lib.lookupFunction<_SemWaitC, _SemWaitDart>('sem_wait'),
        semPost = lib.lookupFunction<_SemPostC, _SemPostDart>('sem_post'),
        semClose = lib.lookupFunction<_SemCloseC, _SemCloseDart>('sem_close');
}

/// Generic IPC interface unifying Win32 and POSIX shared memory implementations.
abstract interface class _Vst3Ipc {
  Pointer<Void> get pointer;
  void waitReady();
  void signalDone();
  void dispose();
}

final class _PosixIpc implements _Vst3Ipc {
  final Pointer<Void> _ptr;
  final int _fd;
  final Pointer<Void> _semReady;
  final Pointer<Void> _semDone;
  final _PosixNative _native;

  _PosixIpc(this._ptr, this._fd, this._semReady, this._semDone, this._native);

  @override
  Pointer<Void> get pointer => _ptr;

  @override
  void waitReady() => _native.semWait(_semReady);

  @override
  void signalDone() => _native.semPost(_semDone);

  @override
  void dispose() {
    _native.semClose(_semReady);
    _native.semClose(_semDone);
    _native.munmap(_ptr, _vst3ShmTotalSize);
    _native.close(_fd);
  }
}

final class _Win32Ipc implements _Vst3Ipc {
  final Pointer<Void> _hMap;
  final Pointer<Void> _ptr;
  final Pointer<Void> _hSemReady;
  final Pointer<Void> _hSemDone;

  final int Function(Pointer<Void>, int) _waitForSingleObject;
  final int Function(Pointer<Void>, int, Pointer<Int32>) _releaseSemaphore;
  final int Function(Pointer<Void>) _unmapViewOfFile;
  final int Function(Pointer<Void>) _closeHandle;

  _Win32Ipc({
    required Pointer<Void> hMap,
    required Pointer<Void> ptr,
    required Pointer<Void> hSemReady,
    required Pointer<Void> hSemDone,
    required int Function(Pointer<Void>, int) waitForSingleObject,
    required int Function(Pointer<Void>, int, Pointer<Int32>) releaseSemaphore,
    required int Function(Pointer<Void>) unmapViewOfFile,
    required int Function(Pointer<Void>) closeHandle,
  })  : _hMap = hMap,
        _ptr = ptr,
        _hSemReady = hSemReady,
        _hSemDone = hSemDone,
        _waitForSingleObject = waitForSingleObject,
        _releaseSemaphore = releaseSemaphore,
        _unmapViewOfFile = unmapViewOfFile,
        _closeHandle = closeHandle;

  @override
  Pointer<Void> get pointer => _ptr;

  @override
  void waitReady() {
    _waitForSingleObject(_hSemReady, 0xFFFFFFFF); // INFINITE
  }

  @override
  void signalDone() {
    _releaseSemaphore(_hSemDone, 1, nullptr);
  }

  @override
  void dispose() {
    _unmapViewOfFile(_ptr);
    _closeHandle(_hMap);
    _closeHandle(_hSemReady);
    _closeHandle(_hSemDone);
  }
}

_PosixIpc _openPosixIpc(String shmName, String semReadyName, String semDoneName) {
  final posix = _PosixNative(DynamicLibrary.process());
  final shmNameNative = shmName.toNativeUtf8();
  final semRNameNative = semReadyName.toNativeUtf8();
  final semDNameNative = semDoneName.toNativeUtf8();

  try {
    final fd = posix.shmOpen(shmNameNative, 2, 0); // O_RDWR = 2
    if (fd < 0) throw StateError('Failed to open shared memory: $shmName');

    final ptr = posix.mmap(nullptr, _vst3ShmTotalSize, 3, 1, fd, 0);
    if (ptr == nullptr) {
      posix.close(fd);
      throw StateError('Failed to mmap shared memory: $shmName');
    }

    final semReady = posix.semOpen(semRNameNative, 0);
    final semDone = posix.semOpen(semDNameNative, 0);

    return _PosixIpc(ptr, fd, semReady, semDone, posix);
  } finally {
    calloc.free(shmNameNative);
    calloc.free(semRNameNative);
    calloc.free(semDNameNative);
  }
}

_Win32Ipc _openWin32Ipc(String shmName, String semReadyName, String semDoneName) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final openFileMapping = k32.lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Pointer<Utf8>),
      Pointer<Void> Function(int, int, Pointer<Utf8>)>('OpenFileMappingA');
  final mapViewOfFile = k32.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint32, Uint32, Uint32, IntPtr),
      Pointer<Void> Function(Pointer<Void>, int, int, int, int)>('MapViewOfFile');
  final unmapViewOfFile = k32.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('UnmapViewOfFile');
  final closeHandle = k32.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CloseHandle');
  final openSemaphore = k32.lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Pointer<Utf8>),
      Pointer<Void> Function(int, int, Pointer<Utf8>)>('OpenSemaphoreA');
  final waitForSingleObject = k32.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('WaitForSingleObject');
  final releaseSemaphore = k32.lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<Int32>),
      int Function(Pointer<Void>, int, Pointer<Int32>)>('ReleaseSemaphore');

  final shmUtf8 = shmName.toNativeUtf8();
  final semRUtf8 = semReadyName.toNativeUtf8();
  final semDUtf8 = semDoneName.toNativeUtf8();

  try {
    final hMap = openFileMapping(0x000F001F, 0, shmUtf8); // FILE_MAP_ALL_ACCESS
    if (hMap == nullptr) {
      throw StateError('Failed to open Win32 shared memory: $shmName');
    }
    final ptr = mapViewOfFile(hMap, 0x000F001F, 0, 0, _vst3ShmTotalSize);
    if (ptr == nullptr) {
      closeHandle(hMap);
      throw StateError('Failed to map Win32 shared memory: $shmName');
    }
    final hReady = openSemaphore(0x001F0003, 0, semRUtf8); // SEMAPHORE_ALL_ACCESS
    if (hReady == nullptr) {
      unmapViewOfFile(ptr);
      closeHandle(hMap);
      throw StateError('Failed to open Win32 semaphore: $semReadyName');
    }
    final hDone = openSemaphore(0x001F0003, 0, semDUtf8);
    if (hDone == nullptr) {
      closeHandle(hReady);
      unmapViewOfFile(ptr);
      closeHandle(hMap);
      throw StateError('Failed to open Win32 semaphore: $semDoneName');
    }

    return _Win32Ipc(
      hMap: hMap,
      ptr: ptr,
      hSemReady: hReady,
      hSemDone: hDone,
      waitForSingleObject: waitForSingleObject,
      releaseSemaphore: releaseSemaphore,
      unmapViewOfFile: unmapViewOfFile,
      closeHandle: closeHandle,
    );
  } finally {
    calloc.free(shmUtf8);
    calloc.free(semRUtf8);
    calloc.free(semDUtf8);
  }
}

/// Runs a VST3 audio processor using preallocated zero-copy shared memory.
void runVst3SharedMemoryProcessor({
  required List<String> args,
  required dynamic processor,
}) {
  switch (args.length >= 3) {
    case true:
      _startProcessing(args[0], args[1], args[2], processor);
    case false:
      throw ArgumentError(
        'Usage: processor <shm_name> <sem_ready_name> <sem_done_name>',
      );
  }
}

/// Opens the shared memory and semaphore handles, then starts the event loop.
void _startProcessing(
  String shmName,
  String semReadyName,
  String semDoneName,
  dynamic processor,
) {
  final _Vst3Ipc ipc = Platform.isWindows
      ? _openWin32Ipc(shmName, semReadyName, semDoneName)
      : _openPosixIpc(shmName, semReadyName, semDoneName);

  _validateMagic(ipc.pointer);
  _runEventLoop(ipc, processor);
}

/// Verifies that the shared memory block contains the expected VST3 magic word.
void _validateMagic(Pointer<Void> ptr) {
  final magic = Pointer<Uint32>.fromAddress(ptr.address + _offsetMagic).value;
  switch (magic == _vst3ShmMagic) {
    case true:
      return;
    case false:
      throw StateError('Invalid VST3 shared memory magic: $magic');
  }
}

/// Performs initialization handshake with host, enters DSP loop, and cleans up.
void _runEventLoop(_Vst3Ipc ipc, dynamic processor) {
  final ptr = ipc.pointer;
  final sampleRate = Pointer<Double>.fromAddress(ptr.address + _offsetSampleRate).value;
  final maxBlockSize = Pointer<Uint32>.fromAddress(ptr.address + _offsetMaxBlockSize).value;
  processor.initialize(sampleRate, maxBlockSize);
  ipc.signalDone(); // Signal C++ host that initialization is complete

  _processingLoop(ipc, processor);
  _dispose(ipc, processor);
}

/// Core audio processing loop waiting on semReady and signaling semDone.
void _processingLoop(_Vst3Ipc ipc, dynamic processor) {
  final ptr = ipc.pointer;
  var running = true;
  while (running) {
    ipc.waitReady();
    final cmd = Pointer<Uint32>.fromAddress(ptr.address + _offsetCommand).value;
    switch (cmd) {
      case _vst3CmdProcess:
        _handleProcessBlock(ptr, processor);
        ipc.signalDone();
        break;
      case _vst3CmdTerminate:
        running = false;
        break;
      default:
        ipc.signalDone();
        break;
    }
  }
}

/// Drains parameters from the ring buffer and processes stereo audio in-place.
void _handleProcessBlock(Pointer<Void> ptr, dynamic processor) {
  _drainParameters(ptr, processor);
  final numSamples = Pointer<Int32>.fromAddress(ptr.address + _offsetNumSamples).value;
  final inL = Pointer<Float>.fromAddress(ptr.address + _offsetInputL).asTypedList(numSamples);
  final inR = Pointer<Float>.fromAddress(ptr.address + _offsetInputR).asTypedList(numSamples);
  final outL = Pointer<Float>.fromAddress(ptr.address + _offsetOutputL).asTypedList(numSamples);
  final outR = Pointer<Float>.fromAddress(ptr.address + _offsetOutputR).asTypedList(numSamples);
  processor.processStereo(inL, inR, outL, outR);
}

/// Drains pending parameter automation events from the host lock-free ring buffer.
void _drainParameters(Pointer<Void> ptr, dynamic processor) {
  final writeIdx = Pointer<Uint32>.fromAddress(ptr.address + _offsetHostParamWrite).value;
  var readIdx = Pointer<Uint32>.fromAddress(ptr.address + _offsetHostParamRead).value;

  while (readIdx != writeIdx) {
    final eventOffset = _offsetHostParams + ((readIdx % 64) * 16);
    final paramId = Pointer<Int32>.fromAddress(ptr.address + eventOffset).value;
    final value = Pointer<Double>.fromAddress(ptr.address + eventOffset + 8).value;
    processor.setParameter(paramId, value);
    readIdx++;
  }
  Pointer<Uint32>.fromAddress(ptr.address + _offsetHostParamRead).value = readIdx;
}

/// Cleans up shared memory mappings, closes semaphores, and exits process.
void _dispose(_Vst3Ipc ipc, dynamic processor) {
  processor.dispose();
  ipc.dispose();
  exit(0);
}
