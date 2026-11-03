import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/vst3_worker_loop.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';
import 'package:flutter_vst3/src/vst3_shared_memory_processor.dart';

import 'shm_test_harness.dart';

class _Processor implements Vst3WorkerProcessor {
  final events = <(int, double)>[];
  final calls = <String>[];
  @override
  void initialize(double rate, int size) => calls.add('$rate/$size');
  @override
  void setParameter(int id, double value) => events.add((id, value));
  @override
  void reset() => calls.add('reset');
  @override
  void dispose() => calls.add('dispose');
  @override
  void processStereo(
      Float32List a, Float32List b, Float32List c, Float32List d) {
    calls.add('process/${a.length}');
  }
}

void main() {
  test('an interrupted ready wait restarts, any other failure throws '
      '[IPC-SYNC-HANDOFF]', () {
    for (final interruptions in [0, 1, 2, 50]) {
      var waits = 0;
      retryOnSemEintr(
          () => ++waits <= interruptions ? -1 : 0, () => vst3SemWaitEintr);
      expect(waits, interruptions + 1);
    }
    for (final errno in [22, 5, 1]) {
      var waits = 0;
      expect(
          () => retryOnSemEintr(() {
                waits++;
                return -1;
              }, () => errno),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('errno $errno'))));
      expect(waits, 1);
    }
  });

  test('parameter ring crosses uint32 wrap and writes read index', () async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_wrapProbe, port.sendPort);
    addTearDown(() {
      isolate.kill(priority: Isolate.immediate);
      port.close();
    });
    final result = await port.first.timeout(const Duration(seconds: 3)) as (
      List<(int, double)>,
      int,
      int
    );
    expect(result.$1, [(10, 0.0), (11, 0.25), (12, 0.5)]);
    expect(result.$2, 1);
    expect(result.$3, 3);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test('header requires both magic and protocol version', () {
    final memory = calloc<Uint8>(vst3ShmTotalSize);
    addTearDown(() => calloc.free(memory));
    expect(() => validateShmHeader(memory.cast()), throwsStateError);
    writeLiveMagicExpectingVersionReject(memory);
    expect(() => validateShmHeader(memory.cast()), returnsNormally);
  });

  test('commands and view reuse', () {
    final memory = shmBlock();
    final processor = _Processor();
    final views = Vst3BlockViews(memory.cast());
    writeF64(memory, vst3OffsetSampleRate, 96000);
    writeU32(memory, vst3OffsetMaxBlockSize, 256);
    writeI32(memory, vst3OffsetNumSamples, 8);
    for (final command in [
      0,
      vst3CmdConfigure,
      vst3CmdReset,
      vst3CmdProcess,
      vst3CmdTerminate
    ]) {
      writeU32(memory, vst3OffsetCommand, command);
      expect(handleCommand(memory.cast(), views, processor),
          command != vst3CmdTerminate);
    }
    expect(processor.calls, ['96000.0/256', 'reset', 'process/8']);
    final originals = [views.inL, views.inR, views.outL, views.outR];
    _assertRouting(memory, originals);
    views.resize(8);
    final current = [views.inL, views.inR, views.outL, views.outR];
    for (var i = 0; i < 4; i++) {
      expect(identical(originals[i], current[i]), isTrue);
    }
    views.resize(4);
    expect(identical(originals[0], views.inL), isFalse);
    expect(views.inL.length, 4);
  });

  test('POSIX failure sentinels are checked without dereferencing', () {
    expect(() => throwIfMapFailed(Pointer.fromAddress(-1), 'test'),
        throwsStateError);
    expect(() => throwIfMapFailed(nullptr, 'test'), returnsNormally);
    expect(() => throwIfMapFailed(Pointer.fromAddress(1234), 'test'),
        returnsNormally);
    for (final address in [-1, 0]) {
      expect(() => throwIfSemFailed(Pointer.fromAddress(address), 'test'),
          throwsStateError);
    }
    expect(() => throwIfSemFailed(Pointer.fromAddress(1234), 'test'),
        returnsNormally);
  });
}

void _assertRouting(Pointer<Uint8> memory, List<Float32List> views) {
  fillChannels(memory, samples: 8, scale: 100, base: 0.25);
  for (var channel = 0; channel < channelOffsets.length; channel++) {
    expect(views[channel],
        [for (var sample = 0; sample < 8; sample++) channel * 100 + sample + 0.25]);
    views[channel][7] = channel * 1000 + 0.5;
    expect(readF32(memory, channelOffsets[channel], 7), channel * 1000 + 0.5);
  }
}

void _wrapProbe(SendPort port) {
  final memory = calloc<Uint8>(vst3ShmTotalSize);

  final processor = _Processor();
  writeU32(memory, vst3OffsetHostParamRead, 0xfffffffe);
  writeU32(memory, vst3OffsetHostParamWrite, 1);
  for (var i = 0; i < 3; i++) {
    final slot = ((0xfffffffe + i) & 0xffffffff) % vst3ShmParamQueueSize;
    final event = vst3OffsetHostParams + slot * vst3ShmParamEventSize;
    writeI32(memory, event, 10 + i);
    writeF64(memory, event + 8, i / 4);
  }
  drainHostParameters(memory.cast(), processor);
  final firstEvents = List.of(processor.events);
  final index =
      Pointer<Uint32>.fromAddress(memory.address + vst3OffsetHostParamRead)
          .value;
  drainHostParameters(memory.cast(), processor);
  port.send((firstEvents, index, processor.events.length));
  calloc.free(memory);
}
