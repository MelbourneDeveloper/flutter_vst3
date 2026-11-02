import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _metadata({
  String bundle = 'com.test.alpha',
  String? entrypoint,
  List<int> ids = const [0, 1],
}) =>
    {
      'pluginName': 'Alpha',
      'vendor': 'Test',
      'version': '1.0.0',
      'category': 'Fx',
      'bundleIdentifier': bundle,
      'companyWeb': 'https://example.com',
      'companyEmail': 'a@example.com',
      if (entrypoint != null) 'flutterEntrypoint': entrypoint,
      'parameters': [
        for (final id in ids)
          {
            'id': id,
            'name': 'param$id',
            'defaultValue': 0.25,
            'units': '%',
          },
      ],
    };

ProcessResult _generate(Directory dir, Map<String, dynamic> metadata) {
  File('${dir.path}/plugin_metadata.json')
      .writeAsStringSync(jsonEncode(metadata));
  return Process.runSync(
    'dart',
    ['scripts/generate_plugin.dart', dir.path, 'alpha', 'alpha', dir.path],
  );
}

String _generated(Directory dir, String name) =>
    File('${dir.path}/generated/$name').readAsStringSync();

void main() {
  var dir = Directory.current;

  setUp(() => dir = Directory.systemTemp.createTempSync('vst3_generate'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('generates a processor with no unresolved placeholders', () {
    final result = _generate(dir, _metadata());
    expect(result.exitCode, 0, reason: '${result.stdout}');
    final processor = _generated(dir, 'alpha_processor.cpp');
    expect(processor, isNot(contains('{{')));
    expect(processor, contains('kParameterDefaults{ 0.25, 0.25 }'));
    expect(processor, contains('vst3WorkerPathNextToModule("alpha_processor")'));
  });

  test('H25: UIDs differ by plugin, and are stable', () {
    expect(_generate(dir, _metadata()).exitCode, 0);
    final first = _generated(dir, 'alpha_ids.h');
    expect(_generate(dir, _metadata()).exitCode, 0);
    expect(_generated(dir, 'alpha_ids.h'), first);
    expect(_generate(dir, _metadata(bundle: 'com.test.beta')).exitCode, 0);
    final other = _generated(dir, 'alpha_ids.h');
    final uids = RegExp(r'UID\((.*)\);');
    final firstUids = uids.allMatches(first).map((m) => m.group(1)).toList();
    final otherUids = uids.allMatches(other).map((m) => m.group(1)).toList();
    expect(firstUids, hasLength(2));
    expect(firstUids[0], isNot(firstUids[1]));
    expect(otherUids[0], isNot(firstUids[0]));
    expect(otherUids[1], isNot(firstUids[1]));
  });

  test('H25: a pinned UID is used exactly', () {
    final metadata = _metadata()
      ..['processorUid'] = 'F9D0C991074C84044D825FC521E8F92B'
      ..['controllerUid'] = 'A011573216F065964B9846B6007933D0';
    expect(_generate(dir, metadata).exitCode, 0);
    final ids = _generated(dir, 'alpha_ids.h');
    expect(ids, contains('kAlphaProcessorUID(0xF9D0C991, 0x074C8404, 0x4D825FC5, 0x21E8F92B);'));
    expect(ids, contains('kAlphaControllerUID(0xA0115732, 0x16F06596, 0x4B9846B6, 0x007933D0);'));
  });

  test('H25: a bad pinned UID is rejected', () {
    const good = 'F9D0C991074C84044D825FC521E8F92B';
    const other = 'A011573216F065964B9846B6007933D0';
    final cases = <(Map<String, Object>, String)>[
      ({'processorUid': good}, 'processorUid and controllerUid must be set together'),
      ({'controllerUid': good}, 'processorUid and controllerUid must be set together'),
      ({'processorUid': good, 'controllerUid': good}, 'processorUid and controllerUid must differ'),
      ({'processorUid': 'F9D0', 'controllerUid': other}, 'processorUid must be 32 hex digits'),
      ({'processorUid': good, 'controllerUid': 'not hex at all, but thirty two!!'}, 'controllerUid must be 32 hex digits'),
      ({'processorUid': 7, 'controllerUid': other}, 'processorUid must be 32 hex digits'),
    ];
    for (final (uids, message) in cases) {
      final result = _generate(dir, _metadata()..addAll(uids));
      expect(result.exitCode, isNot(0), reason: '$uids');
      expect('${result.stdout}', contains(message));
    }
  });

  test('H25: Echo keeps its original UIDs, and Reverb has its own', () {
    Map<String, dynamic> real(String name) =>
        jsonDecode(File('../vsts/$name/plugin_metadata.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(_generate(dir, real('echo')).exitCode, 0);
    final echo = _generated(dir, 'alpha_ids.h');
    expect(echo, contains('ProcessorUID(0xF9D0C991, 0x074C8404, 0x4D825FC5, 0x21E8F92B);'));
    expect(echo, contains('ControllerUID(0xA0115732, 0x16F06596, 0x4B9846B6, 0x007933D0);'));
    expect(_generate(dir, real('flutter_reverb')).exitCode, 0);
    final reverb = _generated(dir, 'alpha_ids.h');
    expect(reverb, isNot(contains('0xF9D0C991, 0x074C8404, 0x4D825FC5, 0x21E8F92B')));
    expect(reverb, isNot(contains('0xA0115732, 0x16F06596, 0x4B9846B6, 0x007933D0')));
  });

  test('B12: the Flutter entrypoint reaches the CMake metadata', () {
    expect(_generate(dir, _metadata(entrypoint: 'alphaMain')).exitCode, 0);
    expect(
      _generated(dir, 'metadata.cmake'),
      contains('set(JSON_FLUTTER_ENTRYPOINT "alphaMain")'),
    );
    expect(_generate(dir, _metadata()).exitCode, 0);
    expect(
      _generated(dir, 'metadata.cmake'),
      contains('set(JSON_FLUTTER_ENTRYPOINT "")'),
    );
  });

  test('rejects parameter ids that are not 0..n-1', () {
    final result = _generate(dir, _metadata(ids: [0, 2]));
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}', contains('Parameter ids must be 0..n-1'));
  });
}
