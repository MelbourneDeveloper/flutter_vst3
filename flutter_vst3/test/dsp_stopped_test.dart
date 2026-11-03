import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/parameter_binding.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';

const _channel = MethodChannel('flutter_vst3/parameters');
final _messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a block with a cleared magic word means the worker died', () async {
    final first = calloc<Uint8>(vst3ShmTotalSize);
    final second = calloc<Uint8>(vst3ShmTotalSize);
    addTearDown(() {
      calloc.free(first);
      calloc.free(second);
    });
    first.cast<Uint32>().value = vst3ShmMagic;
    second.cast<Uint32>().value = vst3ShmMagic;
    var address = first.address;
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      return switch (call.method) {
        'getSharedMemoryInfo' => {'address': address},
        'getInitialParameters' => <Object?, Object?>{},
        _ => null,
      };
    });
    final binding = VST3ParameterBinding.getInstance();
    await binding.loadInitialParameters();
    var notified = 0;
    void listener() => notified++;
    binding.addListener(listener);
    addTearDown(() => binding.removeListener(listener));
    Future<void> refresh() => binding.getAudioBufferReader(forceRefresh: true);

    await refresh();
    expect(binding.dspStopped, isFalse);
    expect(notified, 0);

    first.cast<Uint32>().value = 0;
    await refresh();
    expect(binding.dspStopped, isTrue);
    expect(notified, 1);

    await refresh();
    expect(binding.dspStopped, isTrue);
    expect(notified, 1, reason: 'no change means no notification');

    address = second.address;
    await refresh();
    expect(binding.dspStopped, isFalse);
    expect(notified, 2);

    address = 0;
    await refresh();
    expect(binding.dspStopped, isFalse, reason: 'deactivated is not stopped');
    expect(notified, 2);

    address = first.address;
    await refresh();
    expect(binding.dspStopped, isTrue);
    expect(notified, 3);

    _messenger.setMockMethodCallHandler(_channel, null);
    await refresh();
    expect(binding.dspStopped, isTrue, reason: 'no reply changes nothing');
    expect(notified, 3);
  });
}
