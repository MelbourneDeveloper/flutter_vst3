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
