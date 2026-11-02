import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/parameter_binding.dart';

const _channel = MethodChannel('flutter_vst3/parameters');
const _codec = StandardMethodCodec();
final _messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
Object? _initial = <Object?, Object?>{'0': 0.25, '2': 0.5};
final _calls = <MethodCall>[];
final _values = <double>[];

Future<Object?> _incoming(Object? args) async {
  Object? result;
  await _messenger.handlePlatformMessage(_channel.name,
      _codec.encodeMethodCall(MethodCall('onParameterChanged', args)),
      (data) => result = data == null ? null : _codec.decodeEnvelope(data));
  return result;
}

Future<void> _outgoing(VST3ParameterBinding binding) async {
  _calls.clear();
  await binding.beginEdit(2);
  await binding.setParameter(2, 0.7);
  await binding.setParameter(2, -1);
  await binding.setParameter(2, 2);
  await binding.endEdit(2);
  expect(_calls.map((c) => c.method).toList(),
      ['beginEdit', 'setParameter', 'setParameter', 'setParameter', 'endEdit']);
  expect(_calls.map((c) => c.arguments).toList(), [
    {'id': 2}, {'id': 2, 'value': 0.7}, {'id': 2, 'value': 0.0},
    {'id': 2, 'value': 1.0}, {'id': 2}
  ]);
  expect(binding.getParameter(2), 1);
  expect(_values, [0.7, 0, 1]);
}

Future<void> _rejectMessages(VST3ParameterBinding binding) async {
  for (final bad in [
    {'id': 2, 'value': 2.0}, {'id': 2, 'value': -1.0},
    {'id': 2, 'value': double.nan}, {'id': '2', 'value': 0.2},
    {'id': 4, 'value': 0.2}, {'id': -1, 'value': 0.2},
    {'id': 2.5, 'value': 0.2}, {'id': 2, 'value': 'bad'}, [], null
  ]) {
    await expectLater(_incoming(bad), throwsA(isA<PlatformException>()));
    expect(binding.getParameter(2), 0.3);
    expect(_values, [0.7, 0, 1, 0.3]);
  }
}

Future<void> _rejectInitial(VST3ParameterBinding binding) async {
  final badValues = [2.0, -1.0, double.nan, 'bad'];
  final badMaps = [
    for (final bad in badValues) {0: 0.9, 2: bad},
    {0: 0.9, '2.0': 0.2}, {0: 0.9, 'bad': 0.2},
    {0: 0.9, 4: 0.2}, {0: 0.9, 2.5: 0.2}, null, []
  ];
  for (final bad in badMaps) {
    _initial = bad;
    await expectLater(binding.loadInitialParameters(), throwsArgumentError);
    expect(binding.getParameter(0), 0.25);
    expect(binding.getParameter(2), 0.3);
    expect(_values, [0.7, 0, 1, 0.3]);
  }
}

Future<VST3ParameterBinding> _setup() async {
  _messenger.setMockMethodCallHandler(_channel, (call) async {
    _calls.add(call);
    return call.method == 'getInitialParameters' ? _initial : null;
  });
  final binding = VST3ParameterBinding.getInstance(paramCount: 4);
  await binding.loadInitialParameters();
  void listener() => _values.add(binding.getParameter(2));
  binding.addListener(listener);
  addTearDown(() => binding.removeListener(listener));
  expect(binding.getParameter(0), 0.25);
  expect(binding.getParameter(2), 0.5);
  return binding;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exact bidirectional contract and atomic rejection', () async {
    final binding = await _setup();
    await _outgoing(binding);
    await _incoming({'id': 2, 'value': 0.3});
    expect(binding.getParameter(2), 0.3);
    expect(_values, [0.7, 0, 1, 0.3]);
    await _rejectMessages(binding);
    await _rejectInitial(binding);
  });
  test('a gesture reaches the host only once a value changes', () async {
    _initial = const <Object?, Object?>{'0': 0.25, '2': 0.5};
    final binding = await _setup();
    _calls.clear();
    await binding.beginEdit(1);
    await binding.endEdit(1);
    expect(_calls, isEmpty);
    await binding.beginEdit(1);
    expect(_calls, isEmpty);
    await binding.setParameter(1, 0.4);
    await binding.setParameter(1, 0.5);
    await binding.endEdit(1);
    expect(_calls.map((c) => c.method).toList(),
        ['beginEdit', 'setParameter', 'setParameter', 'endEdit']);
    expect(_calls.map((c) => c.arguments).toList(), [
      {'id': 1}, {'id': 1, 'value': 0.4}, {'id': 1, 'value': 0.5}, {'id': 1}
    ]);
  });
  test('closing the editor forgets a gesture that has not started', () async {
    _initial = const <Object?, Object?>{'0': 0.25, '2': 0.5};
    final binding = await _setup();
    _calls.clear();
    await binding.beginEdit(1);
    await _messenger.handlePlatformMessage(_channel.name,
        _codec.encodeMethodCall(const MethodCall('onHostDetached')), (_) {});
    await binding.setParameter(1, 0.6);
    expect(_calls.map((c) => c.method).toList(), ['setParameter']);
    await _messenger.handlePlatformMessage(_channel.name,
        _codec.encodeMethodCall(const MethodCall('onHostAttached')), (_) {});
  });
  test('running without a host keeps the cache and throws nothing', () async {
    _initial = const <Object?, Object?>{'0': 0.25, '2': 0.5};
    final binding = await _setup();
    await binding.setParameter(2, 0.6);
    final notified = _values.length;
    _messenger.setMockMethodCallHandler(_channel, null);
    await binding.loadInitialParameters();
    expect(binding.getParameter(0), 0.25);
    expect(binding.getParameter(2), 0.6);
    expect(_values.length, notified);
    await binding.beginEdit(2);
    await binding.setParameter(2, 0.8);
    await binding.endEdit(2);
    expect(binding.getParameter(2), 0.8);
    expect(_values.sublist(notified), [0.8]);
  });
}
