/// High level wrappers over the native VST host bindings. These
/// classes manage resources using RAII and provide idiomatic Dart
/// APIs for loading plug‑ins, controlling parameters and processing
/// audio.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// Represents a running host context. A host owns its VST plug‑ins
/// and must be disposed when no longer needed.
class VstHost {
  final NativeBindings _b;
  final Pointer<Void> handle;

  VstHost._(this._b, this.handle);

  /// Create a new host at the given sample rate and maximum block
  /// size. Optionally specify [dylibPath] to load the native
  /// library from a custom location. Throws StateError on failure.
  static VstHost create({required double sampleRate, required int maxBlock, String? dylibPath}) {
    final b = NativeBindings(loadDvh(path: dylibPath));
    final h = b.dvhCreateHost(sampleRate, maxBlock);
    if (h == nullptr) {
      throw StateError('Failed to create host');
    }
    return VstHost._(b, h);
  }

  /// Release resources associated with this host. After calling
  /// dispose(), the host handle is invalid and should not be used.
  void dispose() {
    _b.dvhDestroyHost(handle);
  }

  /// Load a VST plug‑in from [modulePath]. Optionally specify
  /// [classUid] to select a specific class from a multi‑class module.
  /// Returns a VstPlugin on success; throws StateError on failure.
  VstPlugin load(String modulePath, {String? classUid}) {
    final p = modulePath.toNativeUtf8();
    final uid = classUid == null ? nullptr : classUid.toNativeUtf8();
    final h = _b.dvhLoadPlugin(handle, p, uid);
    malloc.free(p);
    if (uid != nullptr) malloc.free(uid);
    if (h == nullptr) throw StateError('Failed to load plugin');
    return VstPlugin._(_b, h);
  }
}

/// Information about a plug‑in parameter. The [id] can be passed
/// to getParamNormalized() and setParamNormalized().
class ParamInfo {
  final int id;
  final String title;
  final String units;
  ParamInfo(this.id, this.title, this.units);
}

/// Represents a loaded VST plug‑in. Provides methods for
/// starting/stopping processing, handling MIDI events and
/// manipulating parameters. Instances must be unloaded when no
/// longer needed.
class VstPlugin {
  final NativeBindings _b;
  final Pointer<Void> handle;
  VstPlugin._(this._b, this.handle);

  /// Activate the plug‑in with the given sample rate and block size.
  bool resume({required double sampleRate, required int maxBlock}) =>
      _b.dvhResume(handle, sampleRate, maxBlock) == 1;

  /// Deactivate processing. Returns true on success.
  bool suspend() => _b.dvhSuspend(handle) == 1;

  /// Release this plug‑in from the host. After calling unload() the
  /// handle is invalid. Further calls on this instance will throw.
  void unload() => _b.dvhUnloadPlugin(handle);

  /// Number of parameters exposed by this plug‑in.
  int paramCount() => _b.dvhParamCount(handle);

  /// Get information about a parameter by index. Throws StateError if
  /// index is out of range or retrieval fails.
  ParamInfo paramInfoAt(int index) {
    final id = malloc<Int32>();
    final title = malloc.allocate<Utf8>(256);
    final units = malloc.allocate<Utf8>(64);
    try {
      final ok = _b.dvhParamInfo(handle, index, id, title, 256, units, 64) == 1;
      if (!ok) throw StateError('param info failed');
      return ParamInfo(id.value, title.toDartString(), units.toDartString());
    } finally {
      malloc.free(id);
      malloc.free(title);
      malloc.free(units);
    }
  }

  /// Get the normalized value of a parameter by ID.
  double getParamNormalized(int paramId) => _b.dvhGetParam(handle, paramId);

  /// Set the normalized value of a parameter by ID. Returns true on
  /// success.
  bool setParamNormalized(int paramId, double value) =>
      _b.dvhSetParam(handle, paramId, value) == 1;

  /// Send a MIDI note on event. Channel is zero‑based.
  bool noteOn(int channel, int note, double velocity) =>
      _b.dvhNoteOn(handle, channel, note, velocity) == 1;

  /// Send a MIDI note off event.
  bool noteOff(int channel, int note, double velocity) =>
      _b.dvhNoteOff(handle, channel, note, velocity) == 1;

  /// Process a block of stereo audio. The input and output lists must
  /// all have the same length. Returns true on success.
  bool processStereoF32(Float32List inL, Float32List inR, Float32List outL, Float32List outR) {
    if (inL.length != inR.length || inL.length != outL.length || inL.length != outR.length) {
      throw ArgumentError('All buffers must have same length');
    }
    final n = inL.length;
    final pInL = malloc<Float>(n);
    final pInR = malloc<Float>(n);
    final pOutL = malloc<Float>(n);
    final pOutR = malloc<Float>(n);
    try {
      pInL.asTypedList(n).setAll(0, inL);
      pInR.asTypedList(n).setAll(0, inR);
      final ok = _b.dvhProcessStereoF32(handle, pInL, pInR, pOutL, pOutR, n) == 1;
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