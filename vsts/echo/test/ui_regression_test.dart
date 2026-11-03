import 'dart:ffi' hide Size;
import '../../../flutter_vst3/test/support/shared_memory_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/ui.dart';
import 'package:echo/ui/echo_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_vst3/parameters');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var address = 0;
  var fail = false;
  setUp(() {
    calls.clear();
    fail = false;
    address = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'host-failed');
      return switch (call.method) {
        'getInitialParameters' => {'0': 0.5, '1': 0.5, '2': 0.5},
        'getSharedMemoryInfo' => {'address': address},
        _ => null,
      };
    });
  });

  Future<void> host(String method) async {
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {});
  }

  test('physical parameter formatting', () {
    expect(formatEchoParameter(0, 0), '0.0ms');
    expect(formatEchoParameter(0, 0.5), '500.0ms');
    expect(formatEchoParameter(0, 1), '1000.0ms');
    expect(formatEchoParameter(1, 0.25), '25.0%');
    expect(formatEchoParameter(2, 1), '100.0%');
  });

  test('single sample waveform is finite', () {
    final path = buildEchoWaveformPath([0.5], const Size(200, 100));
    final bounds = path.getBounds();
    expect(bounds.left.isFinite, isTrue);
    expect(bounds.top.isFinite, isTrue);
    expect(bounds.left, 0);
    expect(bounds.top, 28);
  });

  testWidgets('one begin/set/end gesture per knob drag and bypass',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EchoUI()));
    await tester.pump();
    calls.clear();
    final knob = find.descendant(
        of: find.byType(RotaryKnob).first, matching: find.byType(CustomPaint));
    final gesture = await tester.startGesture(tester.getCenter(knob));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final edits = calls
        .where(
            (c) => ['beginEdit', 'setParameter', 'endEdit'].contains(c.method))
        .toList();
    expect(edits.first.method, 'beginEdit');
    expect(edits.last.method, 'endEdit');
    expect(edits.where((c) => c.method == 'beginEdit').length, 1);
    expect(edits.where((c) => c.method == 'endEdit').length, 1);
    expect(edits.sublist(1, edits.length - 1), isNotEmpty);
    expect(
        edits
            .sublist(1, edits.length - 1)
            .every((c) => c.method == 'setParameter'),
        isTrue);
    expect(edits.every((c) => (c.arguments as Map)['id'] == 0), isTrue);
    calls.clear();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(
        calls.map((c) => c.method), ['beginEdit', 'setParameter', 'endEdit']);
    expect(calls.map((c) => (c.arguments as Map)['id']), [3, 3, 3]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a valid reader fetches only on attachment, a missing one on the bounded tick',
      (tester) async {
    final memory = allocateSharedMemoryFixture();
    addTearDown(() => freeSharedMemoryFixture(memory));
    memory.cast<Uint32>().value = vst3ShmMagic;
    address = memory.address;
    await host('onHostDetached');
    await host('onHostAttached');
    await tester.pumpWidget(const MaterialApp(home: EchoWaveformVisualizer()));
    await tester.pump();
    int fetches() =>
        calls.where((c) => c.method == 'getSharedMemoryInfo').length;
    expect(fetches(), 1);
    VST3ParameterBinding.getInstance().notifyListeners();
    await tester.pump(const Duration(seconds: 2));
    expect(fetches(), 1);
    memory.cast<Uint32>().value = 0;
    address = 0;
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(fetches(), 2);
    await tester.pump(const Duration(seconds: 2));
    expect(fetches(), 4,
        reason: 'a missing reader retries about once a second, bounded');
    await host('onHostDetached');
    await host('onHostAttached');
    await tester.pump();
    expect(fetches(), 5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an editor opened while inactive picks the wave up at '
      'activation [TELEMETRY-RESTART-POLL] [TELEMETRY-SHM-INFO]', (tester) async {
    final memory = allocateSharedMemoryFixture();
    addTearDown(() => freeSharedMemoryFixture(memory));
    address = 0;
    await host('onHostDetached');
    await host('onHostAttached');
    await tester.pumpWidget(const MaterialApp(home: EchoWaveformVisualizer()));
    await tester.pump();
    int fetches() =>
        calls.where((c) => c.method == 'getSharedMemoryInfo').length;
    CustomPaint scope() => find
        .descendant(
            of: find.byType(EchoWaveformVisualizer),
            matching: find.byType(CustomPaint))
        .evaluate()
        .single
        .widget as CustomPaint;
    expect(fetches(), 1);
    final flatPainter = scope().painter;

    memory.cast<Uint32>().value = vst3ShmMagic;
    Pointer<Int32>.fromAddress(memory.address + vst3OffsetNumSamples).value = 4;
    Pointer<Float>.fromAddress(memory.address + vst3OffsetOutputL)
      ..[0] = 0.5
      ..[1] = -0.5
      ..[2] = 0.5
      ..[3] = -0.5;
    address = memory.address;
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(fetches(), 2,
        reason: 'the missing reader is retried on the bounded tick');
    expect(identical(scope().painter, flatPainter), isFalse,
        reason: 'the scope repaints with the block\'s samples');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('the editor says when the DSP stops, and when it is back',
      (tester) async {
    const message = 'DSP stopped. Audio is silent until the plugin is re-enabled.';
    final memory = allocateSharedMemoryFixture();
    final restarted = allocateSharedMemoryFixture();
    addTearDown(() {
      freeSharedMemoryFixture(memory);
      freeSharedMemoryFixture(restarted);
    });
    memory.cast<Uint32>().value = vst3ShmMagic;
    restarted.cast<Uint32>().value = vst3ShmMagic;
    address = memory.address;
    await host('onHostDetached');
    await host('onHostAttached');
    await tester.pumpWidget(const MaterialApp(home: EchoUI()));
    await tester.pump();
    expect(find.text(message), findsNothing);
    int fetches() =>
        calls.where((c) => c.method == 'getSharedMemoryInfo').length;

    memory.cast<Uint32>().value = 0;
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    final before = fetches();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(fetches() - before, inInclusiveRange(1, 3),
        reason: 'looks for a new worker about once a second, not every frame');
    expect(find.text(message), findsOneWidget);

    address = restarted.address;
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    await tester.pump();
    expect(find.text(message), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('host channel failures propagate to callers', () async {
    final binding = VST3ParameterBinding.getInstance();
    await binding.loadInitialParameters();
    fail = true;
    await expectLater(
        binding.loadInitialParameters(), throwsA(isA<PlatformException>()));
    await expectLater(binding.getAudioBufferReader(forceRefresh: true),
        throwsA(isA<PlatformException>()));
    await expectLater(
        binding.setParameter(0, 0.5), throwsA(isA<PlatformException>()));
    await binding.beginEdit(0);
    await expectLater(
        binding.setParameter(0, 0.6), throwsA(isA<PlatformException>()));
    await expectLater(binding.endEdit(0), throwsA(isA<PlatformException>()));
  });
}
