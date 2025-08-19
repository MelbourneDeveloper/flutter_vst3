import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dart_vst_graph/dart_vst_graph.dart';

/// A simple desktop Flutter UI that lets the user add VST3 modules to
/// the internal graph and adjust the output gain. This interface is
/// not intended to be comprehensive but demonstrates how to build a
/// host controller in Dart.

void main() => runApp(const VstApp());

class VstApp extends StatefulWidget {
  const VstApp({super.key});
  @override
  State<VstApp> createState() => _VstAppState();
}

class _VstAppState extends State<VstApp> {
  late VstGraph graph;
  final nodes = <int, String>{};
  int? inNode;
  int? outNode;
  int? mixNode;
  int? gainNode;

  @override
  void initState() {
    super.initState();
    graph = VstGraph(sampleRate: 48000, maxBlock: 512);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final i = graph.addSplit();
    final m = graph.addMixer(8);
    final g = graph.addGain(0);
    final o = graph.addSplit();
    graph.connect(i, m);
    graph.connect(m, g);
    graph.connect(g, o);
    graph.setIO(inputNode: i, outputNode: o);
    setState(() {
      inNode = i;
      mixNode = m;
      gainNode = g;
      outNode = o;
    });
  }

  @override
  void dispose() {
    graph.dispose();
    super.dispose();
  }

  Future<void> _addVst() async {
    final res = await FilePicker.platform.pickFiles(dialogTitle: 'Select .vst3 module', type: FileType.custom, allowedExtensions: ['vst3']);
    if (res == null) return;
    final id = graph.addVst(res.files.single.path!);
    graph.connect(id, mixNode!);
    setState(() {
      nodes[id] = res.files.single.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart VST Host',
      home: Scaffold(
        appBar: AppBar(title: const Text('Dart VST Host')),
        body: Column(
          children: [
            Row(
              children: [
                ElevatedButton(onPressed: _addVst, child: const Text('Add VST3')),
                const SizedBox(width: 12),
                const Text('Output Gain'),
                Expanded(
                  child: Slider(
                    value: _gainNorm,
                    onChanged: (v) {
                      setState(() => _gainNorm = v);
                      graph.setParam(gainNode!, 0, v);
                    },
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: nodes.entries
                    .map((e) => ListTile(
                          title: Text(e.value),
                          subtitle: Text('Node ${e.key} -> Mixer ${mixNode ?? "-"}'),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _gainNorm = 0.5;
}