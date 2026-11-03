// Copyright (c) 2025
// Shared harness for tests hosting real plugins through the native library.

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:test/test.dart';

import 'plugin_fixture.dart';

/// A host over the real native library at 48 kHz, disposed at test end.
VstHost createHost() {
  final host = VstHost.create(
      sampleRate: 48000, maxBlock: 512, dylibPath: _libraryPath());
  addTearDown(host.dispose);
  return host;
}

/// The [name] fixture plugin loaded into a host, unloaded at test end.
VstPlugin loadFixture(String name) {
  final plugin = createHost().load(pluginFixture(name));
  addTearDown(plugin.unload);
  return plugin;
}

/// Resumes [plugin] at 48 kHz, expecting success, and suspends it at test end.
VstPlugin resumePlugin(VstPlugin plugin) {
  expect(plugin.resume(sampleRate: 48000, maxBlock: 512), isTrue);
  addTearDown(plugin.suspend);
  return plugin;
}

/// Renders one 512-sample block holding a single 0.5 impulse at sample 0
/// through [plugin], expecting success, and returns both output channels
/// pre-filled with NaN so an unwritten sample fails the caller's assertion.
(Float32List, Float32List) renderStereoImpulse(VstPlugin plugin) {
  final input = Float32List(512)..[0] = 0.5;
  final left = Float32List(512)..fillRange(0, 512, double.nan);
  final right = Float32List(512)..fillRange(0, 512, double.nan);
  expect(plugin.processStereoF32(input, input, left, right), isTrue);
  return (left, right);
}

String _libraryPath() => File(switch (Platform.operatingSystem) {
      'windows' => 'dart_vst_host.dll',
      'macos' => 'libdart_vst_host.dylib',
      'linux' => 'libdart_vst_host.so',
      _ => throw UnsupportedError('Unsupported platform'),
    }).absolute.path;
