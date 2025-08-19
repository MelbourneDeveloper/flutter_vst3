/// FFI bindings to the graph API defined in dvh_graph.h. This file
/// exposes a low level Dart interface to the native audio graph which
/// allows adding nodes, connecting them and processing audio. See
/// VstGraph below for a higher level wrapper.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _GraphCreateC = Pointer<Void> Function(Double, Int32);
typedef _GraphDestroyC = Void Function(Pointer<Void>);
typedef _GraphClearC = Int32 Function(Pointer<Void>);
typedef _AddVstC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Int32>);
typedef _AddMixerC = Int32 Function(Pointer<Void>, Int32, Pointer<Int32>);
typedef _AddSplitC = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _AddGainC = Int32 Function(Pointer<Void>, Float, Pointer<Int32>);
typedef _ConnC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32);
typedef _SetIO = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _NoteC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, Float);
typedef _ParamCountC = Int32 Function(Pointer<Void>, Int32);
typedef _ParamInfoC = Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Int32>, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32);
typedef _GetParamC = Float Function(Pointer<Void>, Int32, Int32);
typedef _SetParamC = Int32 Function(Pointer<Void>, Int32, Int32, Float);
typedef _LatencyC = Int32 Function(Pointer<Void>);
typedef _ProcessC = Int32 Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Int32);

class GraphBindings {
  final DynamicLibrary lib;
  GraphBindings(this.lib);

  late final Pointer<Void> Function(double, int) create =
      lib.lookupFunction<_GraphCreateC, Pointer<Void> Function(double, int)>('dvh_graph_create');
  late final void Function(Pointer<Void>) destroy =
      lib.lookupFunction<_GraphDestroyC, void Function(Pointer<Void>)>('dvh_graph_destroy');
  late final int Function(Pointer<Void>) clear =
      lib.lookupFunction<_GraphClearC, int Function(Pointer<Void>)>('dvh_graph_clear');

  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Int32>) addVst =
      lib.lookupFunction<_AddVstC, int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Int32>)>('dvh_graph_add_vst');
  late final int Function(Pointer<Void>, int, Pointer<Int32>) addMixer =
      lib.lookupFunction<_AddMixerC, int Function(Pointer<Void>, int, Pointer<Int32>)>('dvh_graph_add_mixer');
  late final int Function(Pointer<Void>, Pointer<Int32>) addSplit =
      lib.lookupFunction<_AddSplitC, int Function(Pointer<Void>, Pointer<Int32>)>('dvh_graph_add_split');
  late final int Function(Pointer<Void>, double, Pointer<Int32>) addGain =
      lib.lookupFunction<_AddGainC, int Function(Pointer<Void>, double, Pointer<Int32>)>('dvh_graph_add_gain');

  late final int Function(Pointer<Void>, int, int, int, int) connect =
      lib.lookupFunction<_ConnC, int Function(Pointer<Void>, int, int, int, int)>('dvh_graph_connect');
  late final int Function(Pointer<Void>, int, int, int, int) disconnect =
      lib.lookupFunction<_ConnC, int Function(Pointer<Void>, int, int, int, int)>('dvh_graph_disconnect');
  late final int Function(Pointer<Void>, int, int) setIO =
      lib.lookupFunction<_SetIO, int Function(Pointer<Void>, int, int)>('dvh_graph_set_io_nodes');

  late final int Function(Pointer<Void>, int, int, int, double) noteOn =
      lib.lookupFunction<_NoteC, int Function(Pointer<Void>, int, int, int, double)>('dvh_graph_note_on');
  late final int Function(Pointer<Void>, int, int, int, double) noteOff =
      lib.lookupFunction<_NoteC, int Function(Pointer<Void>, int, int, int, double)>('dvh_graph_note_off');

  late final int Function(Pointer<Void>, int) paramCount =
      lib.lookupFunction<_ParamCountC, int Function(Pointer<Void>, int)>('dvh_graph_param_count');
  late final int Function(Pointer<Void>, int, int, Pointer<Int32>, Pointer<Utf8>, int, Pointer<Utf8>, int) paramInfo =
      lib.lookupFunction<_ParamInfoC, int Function(Pointer<Void>, int, int, Pointer<Int32>, Pointer<Utf8>, int, Pointer<Utf8>, int)>('dvh_graph_param_info');

  late final double Function(Pointer<Void>, int, int) getParam =
      lib.lookupFunction<_GetParamC, double Function(Pointer<Void>, int, int)>('dvh_graph_get_param');
  late final int Function(Pointer<Void>, int, int, double) setParam =
      lib.lookupFunction<_SetParamC, int Function(Pointer<Void>, int, int, double)>('dvh_graph_set_param');

  late final int Function(Pointer<Void>) latency =
      lib.lookupFunction<_LatencyC, int Function(Pointer<Void>)>('dvh_graph_latency');
  late final int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, int) process =
      lib.lookupFunction<_ProcessC, int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, int)>('dvh_graph_process_stereo');
}

/// Helper to load the native library. See dart_vst_host.loadDvh()
/// for details on path selection. This wrapper is duplicated here to
/// avoid depending on dart_vst_host from dart_vst_graph.
DynamicLibrary _openLib({String? path}) {
  if (path != null) return DynamicLibrary.open(path);
  if (Platform.isMacOS) return DynamicLibrary.open('libdart_vst_host.dylib');
  if (Platform.isLinux) return DynamicLibrary.open('libdart_vst_host.so');
  if (Platform.isWindows) return DynamicLibrary.open('dart_vst_host.dll');
  throw UnsupportedError('Unsupported platform');
}

/// High level API wrapping GraphBindings. Manages lifetime and
/// provides convenience methods for graph construction.
class VstGraph {
  final GraphBindings _b;
  final Pointer<Void> handle;
  VstGraph._(this._b, this.handle);
  factory VstGraph({required double sampleRate, required int maxBlock, String? dylibPath}) {
    final b = GraphBindings(_openLib(path: dylibPath));
    final h = b.create(sampleRate, maxBlock);
    if (h == nullptr) throw StateError('graph create failed');
    return VstGraph._(b, h);
  }
  void dispose() => _b.destroy(handle);

  /// Add a VST3 plug‑in to the graph. Returns the new node ID on
  /// success or throws on failure.
  int addVst(String path, {String? classUid}) {
    final p = path.toNativeUtf8();
    final u = classUid == null ? nullptr : classUid.toNativeUtf8();
    final id = malloc<Int32>();
    try {
      final ok = _b.addVst(handle, p, u, id) == 1;
      if (!ok) throw StateError('addVst failed');
      return id.value;
    } finally {
      malloc.free(p);
      if (u != nullptr) malloc.free(u);
      malloc.free(id);
    }
  }

  /// Add a mixer with [inputs] stereo buses. Returns the node ID.
  int addMixer(int inputs) {
    final id = malloc<Int32>();
    try {
      if (_b.addMixer(handle, inputs, id) != 1) throw StateError('addMixer failed');
      return id.value;
    } finally {
      malloc.free(id);
    }
  }
  /// Add a splitter node. Returns the node ID.
  int addSplit() {
    final id = malloc<Int32>();
    try {
      if (_b.addSplit(handle, id) != 1) throw StateError('addSplit failed');
      return id.value;
    } finally {
      malloc.free(id);
    }
  }
  /// Add a gain node with initial dB value. Returns the node ID.
  int addGain(double db) {
    final id = malloc<Int32>();
    try {
      if (_b.addGain(handle, db, id) != 1) throw StateError('addGain failed');
      return id.value;
    } finally {
      malloc.free(id);
    }
  }

  /// Connect source node [src] to destination [dst]. Only a single
  /// stereo bus per node is supported currently. Returns true on
  /// success.
  bool connect(int src, int dst) => _b.connect(handle, src, 0, dst, 0) == 1;

  /// Set which nodes serve as the graph’s input and output. Returns
  /// true on success.
  bool setIO({required int inputNode, required int outputNode}) => _b.setIO(handle, inputNode, outputNode) == 1;

  /// Set a parameter on a node. Returns true on success.
  bool setParam(int node, int paramId, double v) => _b.setParam(handle, node, paramId, v) == 1;

  /// Process a block of audio. The length of the output buffers must
  /// match the input length. This method is primarily intended for
  /// testing; real‑time processing in a plug‑in should use the native
  /// graph directly. Returns true on success.
  bool process(Float32List inL, Float32List inR, Float32List outL, Float32List outR) {
    if (inL.length != inR.length || inL.length != outL.length || inL.length != outR.length) {
      throw ArgumentError('Buffers must have same length');
    }
    final n = inL.length;
    final pInL = malloc<Float>(n);
    final pInR = malloc<Float>(n);
    final pOutL = malloc<Float>(n);
    final pOutR = malloc<Float>(n);
    try {
      pInL.asTypedList(n).setAll(0, inL);
      pInR.asTypedList(n).setAll(0, inR);
      final ok = _b.process(handle, pInL, pInR, pOutL, pOutR, n) == 1;
      if (!ok) return false;
      outL.setAll(0, pOutL.asTypedList(n));
      outR.setAll(0, pOutR.asTypedList(n));
      return true;
    } finally {
      malloc.free(pInL);
      malloc.free(pInR);
      malloc.free(pOutL);
      malloc.free(pOutR);
    }
  }
}