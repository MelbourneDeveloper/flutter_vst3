import 'dart:io';
import 'dart:typed_data';
import 'package:dart_vst_host/dart_vst_host.dart';

/// Example command line program that loads a VST3 plug‑in, sends a
/// note and processes one block of audio. Run this with the path to
/// a .vst3 bundle as the last argument. For example:
///   dart example/main.dart /path/to/MyPlugin.vst3
void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Run: dart example/main.dart /path/to/Plugin.vst3');
    exit(64);
  }

  final pluginPath = args.last;
  final host = VstHost.create(sampleRate: 48000, maxBlock: 512);
  final plug = host.load(pluginPath);

  if (!plug.resume(sampleRate: 48000, maxBlock: 512)) {
    stderr.writeln('resume failed');
    exit(1);
  }

  final n = 512;
  final inL = Float32List(n);
  final inR = Float32List(n);
  final outL = Float32List(n);
  final outR = Float32List(n);

  // Play a middle C with velocity 0.8 on channel 0
  plug.noteOn(0, 60, 0.8);

  final ok = plug.processStereoF32(inL, inR, outL, outR);
  stdout.writeln('process ok: $ok, first sample L=${outL[0]}');

  final count = plug.paramCount();
  for (var i = 0; i < count && i < 8; i++) {
    final pi = plug.paramInfoAt(i);
    stdout.writeln('param $i id=${pi.id} "${pi.title}" [${pi.units}] = ${plug.getParamNormalized(pi.id)}');
  }

  plug.suspend();
  plug.unload();
  host.dispose();
}