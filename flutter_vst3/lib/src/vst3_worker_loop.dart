import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'vst3_shm_layout.dart';

/// DSP implementation driven by the worker event loop.
abstract interface class Vst3WorkerProcessor {
  /// Prepares the DSP. Called at startup and again when the host changes the
  /// sample rate or block size.
  void initialize(double sampleRate, int maxBlockSize);

  /// Applies a normalized parameter value.
  void setParameter(int paramId, double value);

  /// Renders one block. All lists have the same length.
  void processStereo(
    Float32List inputL,
    Float32List inputR,
    Float32List outputL,
    Float32List outputR,
  );

  /// Clears DSP state such as delay tails.
  void reset();

  /// Releases resources before the process exits.
  void dispose();
}

/// Operating system handles for one block and its two semaphores.
abstract interface class Vst3Ipc {
  /// Address of the shared block.
  Pointer<Void> get pointer;

  /// Blocks until the host hands over the shared block.
  void waitReady();

  /// Hands the shared block back to the host.
  void signalDone();

  /// Closes all handles.
  void dispose();
}

/// Reads the u32 field at [offset] of the shared block at [ptr].
int shmU32(Pointer<Void> ptr, int offset) =>
    Pointer<Uint32>.fromAddress(ptr.address + offset).value;

/// Reads the i32 field at [offset] of the shared block at [ptr].
int shmI32(Pointer<Void> ptr, int offset) =>
    Pointer<Int32>.fromAddress(ptr.address + offset).value;

/// Reads the f64 field at [offset] of the shared block at [ptr].
double shmF64(Pointer<Void> ptr, int offset) =>
    Pointer<Double>.fromAddress(ptr.address + offset).value;

/// Throws unless [ptr] holds a live block with the expected protocol version.
void validateShmHeader(Pointer<Void> ptr) {
  final magic = shmU32(ptr, vst3OffsetMagic);
  final version = shmU32(ptr, vst3OffsetVersion);
  magic == vst3ShmMagic
      ? null
      : throw StateError('Invalid VST3 shared memory magic: $magic');
  version == vst3ShmVersion
      ? null
      : throw StateError('Unsupported VST3 shared memory version: $version');
}

/// Exit code of a worker stopped by an exception from the DSP.
const vst3WorkerFailureExitCode = 70;

/// Starts watching [hostPid] and runs the worker until the host terminates it.
///
/// [waitForHostExit] runs in a separate isolate so that it can exit the process
/// while this isolate is blocked waiting for the host.
void runWorker(
  Vst3Ipc ipc,
  Vst3WorkerProcessor processor,
  void Function(int) waitForHostExit,
  int hostPid,
) {
  try {
    validateShmHeader(ipc.pointer);
    Isolate.spawn(waitForHostExit, hostPid);
    _configure(ipc.pointer, processor);
    ipc.signalDone(); // Tells the host that startup is complete.
    _processingLoop(ipc, processor);
    processor.dispose();
    ipc.dispose();
  } catch (error, stack) {
    // Exit explicitly. With the watcher isolate running, the host never saw the
    // process end after an uncaught exception on Windows.
    // print is used because it is synchronous and exit would drop stderr.
    // ignore: avoid_print
    print('flutter_vst3 worker failed: $error\n$stack');
    exit(vst3WorkerFailureExitCode);
  }
  exit(0);
}

void _configure(Pointer<Void> ptr, Vst3WorkerProcessor processor) {
  processor.initialize(
    shmF64(ptr, vst3OffsetSampleRate),
    shmU32(ptr, vst3OffsetMaxBlockSize),
  );
}

/// Handles commands until the host asks the worker to terminate. An exception
/// from the DSP reaches [runWorker], which ends the process.
void _processingLoop(Vst3Ipc ipc, Vst3WorkerProcessor processor) {
  final ptr = ipc.pointer;
  final views = Vst3BlockViews(ptr);
  var running = true;
  while (running) {
    ipc.waitReady();
    running = handleCommand(ptr, views, processor);
    running ? ipc.signalDone() : null;
  }
}

/// Runs the command in the block at [ptr]. Returns false on terminate.
bool handleCommand(
  Pointer<Void> ptr,
  Vst3BlockViews views,
  Vst3WorkerProcessor processor,
) {
  final cmd = shmU32(ptr, vst3OffsetCommand);
  switch (cmd) {
    case vst3CmdProcess:
      drainHostParameters(ptr, processor);
      views.resize(blockLength(ptr));
      processor.processStereo(views.inL, views.inR, views.outL, views.outR);
    case vst3CmdConfigure:
      _configure(ptr, processor);
    case vst3CmdReset:
      processor.reset();
  }
  return cmd != vst3CmdTerminate;
}

/// Returns the block length at [ptr], and throws if it's out of range.
int blockLength(Pointer<Void> ptr) {
  final numSamples = shmI32(ptr, vst3OffsetNumSamples);
  return numSamples >= 0 && numSamples <= vst3ShmMaxSamples
      ? numSamples
      : throw StateError('Invalid block length: $numSamples');
}

/// Views of the audio buffers, recreated only when the block length changes.
final class Vst3BlockViews {
  /// Creates empty views for the block at [_ptr].
  Vst3BlockViews(this._ptr);

  final Pointer<Void> _ptr;
  int _length = -1;
  Float32List _inL = Float32List(0);
  Float32List _inR = Float32List(0);
  Float32List _outL = Float32List(0);
  Float32List _outR = Float32List(0);

  /// Left input.
  Float32List get inL => _inL;

  /// Right input.
  Float32List get inR => _inR;

  /// Left output.
  Float32List get outL => _outL;

  /// Right output.
  Float32List get outR => _outR;

  /// Points the views at [length] samples.
  void resize(int length) {
    switch (length == _length) {
      case true:
        return;
      case false:
        _length = length;
        _inL = _view(vst3OffsetInputL);
        _inR = _view(vst3OffsetInputR);
        _outL = _view(vst3OffsetOutputL);
        _outR = _view(vst3OffsetOutputR);
    }
  }

  Float32List _view(int offset) =>
      Pointer<Float>.fromAddress(_ptr.address + offset).asTypedList(_length);
}

/// Applies queued parameter events from the ring at [ptr] to [processor].
///
/// The ring indices are 32-bit counters that wrap, so the read index is masked
/// after every increment.
void drainHostParameters(Pointer<Void> ptr, Vst3WorkerProcessor processor) {
  final writeIdx = shmU32(ptr, vst3OffsetHostParamWrite);
  final readPtr =
      Pointer<Uint32>.fromAddress(ptr.address + vst3OffsetHostParamRead);
  var readIdx = readPtr.value;
  while (readIdx != writeIdx) {
    final event = vst3OffsetHostParams +
        (readIdx % vst3ShmParamQueueSize) * vst3ShmParamEventSize;
    processor.setParameter(
      shmI32(ptr, event),
      shmF64(ptr, event + 8),
    );
    readIdx = (readIdx + 1) & 0xFFFFFFFF;
  }
  readPtr.value = readIdx;
}
