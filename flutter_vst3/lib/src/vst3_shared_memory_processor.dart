import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'vst3_shm_layout.dart';
import 'vst3_worker_loop.dart';

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

/// Library providing the POSIX IPC symbols. Before glibc 2.34 they live outside
/// libc, where a Dart executable may not have loaded them yet.
DynamicLibrary _posixLibrary() {
  final process = DynamicLibrary.process();
  return process.providesSymbol('shm_open') && process.providesSymbol('sem_open')
      ? process
      : DynamicLibrary.open('librt.so.1');
}

final class _PosixIpc implements Vst3Ipc {
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
    _native.munmap(_ptr, vst3ShmTotalSize);
    _native.close(_fd);
  }
}

final class _Win32Ipc implements Vst3Ipc {
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

/// Throws if [ptr] is mmap's failure value, which is -1 and not null.
void throwIfMapFailed(Pointer<Void> ptr, String name) => ptr.address == -1
    ? throw StateError('Failed to mmap shared memory: $name')
    : null;

/// Throws if [sem] is a sem_open failure value, which is null on Linux and -1
/// on some other POSIX systems.
void throwIfSemFailed(Pointer<Void> sem, String name) =>
    sem.address == 0 || sem.address == -1
        ? throw StateError('Failed to open semaphore: $name')
        : null;

_PosixIpc _openPosixIpc(String shmName, String semReadyName, String semDoneName) {
  final posix = _PosixNative(_posixLibrary());
  final shmNameNative = shmName.toNativeUtf8();
  final semRNameNative = semReadyName.toNativeUtf8();
  final semDNameNative = semDoneName.toNativeUtf8();

  try {
    final fd = posix.shmOpen(shmNameNative, 2, 0); // O_RDWR = 2
    if (fd < 0) throw StateError('Failed to open shared memory: $shmName');

    final ptr = posix.mmap(nullptr, vst3ShmTotalSize, 3, 1, fd, 0);
    throwIfMapFailed(ptr, shmName);

    final semReady = posix.semOpen(semRNameNative, 0);
    throwIfSemFailed(semReady, semReadyName);
    final semDone = posix.semOpen(semDNameNative, 0);
    throwIfSemFailed(semDone, semDoneName);

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
    final ptr = mapViewOfFile(hMap, 0x000F001F, 0, 0, vst3ShmTotalSize);
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

/// Runs [processor] as the DSP worker for one plugin instance.
///
/// [args] are the shared memory name, the two semaphore names and the process
/// id of the host. Blocks until the host terminates the worker, then exits.
void runVst3SharedMemoryProcessor({
  required List<String> args,
  required Vst3WorkerProcessor processor,
}) {
  switch (args.length) {
    case 4:
      final Vst3Ipc ipc = Platform.isWindows
          ? _openWin32Ipc(args[0], args[1], args[2])
          : _openPosixIpc(args[0], args[1], args[2]);
      runWorker(ipc, processor, _exitWhenHostDies, int.parse(args[3]));
    default:
      throw ArgumentError(
        'Usage: processor <shm_name> <sem_ready_name> <sem_done_name> <host_pid>',
      );
  }
}

/// Exits this process when the host process is gone, so that a crashed host
/// can't leave a worker behind on any platform.
void _exitWhenHostDies(int hostPid) {
  switch (Platform.isWindows) {
    case true:
      _waitForWindowsProcess(hostPid);
    case false:
      _waitForPosixParent(hostPid);
  }
  exit(0);
}

void _waitForPosixParent(int hostPid) {
  final getppid = DynamicLibrary.process()
      .lookupFunction<Int32 Function(), int Function()>('getppid');
  while (getppid() == hostPid) {
    sleep(const Duration(milliseconds: 250));
  }
}

void _waitForWindowsProcess(int hostPid) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final openProcess = k32.lookupFunction<
      Pointer<Void> Function(Uint32, Int32, Uint32),
      Pointer<Void> Function(int, int, int)>('OpenProcess');
  final wait = k32.lookupFunction<Uint32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('WaitForSingleObject');
  const synchronize = 0x00100000;
  const infinite = 0xFFFFFFFF;
  final handle = openProcess(synchronize, 0, hostPid);
  handle == nullptr ? null : wait(handle, infinite);
}
