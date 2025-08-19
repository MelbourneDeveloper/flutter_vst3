/// Dart FFI bindings to the native Dart VST host library. This
/// translation mirrors the C API defined in dart_vst_host.h. It
/// provides low‑level functions for creating a host, loading VST
/// plug‑ins and processing audio. Higher level classes are defined
/// in host.dart which wrap these bindings in a safer API.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Type definitions matching the C API signatures. Each typedef
// corresponds to a C function pointer. See dart_vst_host.h for
// documentation on each function.
typedef _HostCreateC = Pointer<Void> Function(Double, Int32);
typedef _HostDestroyC = Void Function(Pointer<Void>);

typedef _LoadC = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _UnloadC = Void Function(Pointer<Void>);

typedef _ResumeC = Int32 Function(Pointer<Void>, Double, Int32);
typedef _SuspendC = Int32 Function(Pointer<Void>);

typedef _ProcessStereoC = Int32 Function(
  Pointer<Void>,
  Pointer<Float>, Pointer<Float>,
  Pointer<Float>, Pointer<Float>,
  Int32);

typedef _NoteC = Int32 Function(Pointer<Void>, Int32, Int32, Float);

typedef _ParamCountC = Int32 Function(Pointer<Void>);
typedef _ParamInfoC = Int32 Function(Pointer<Void>, Int32, Pointer<Int32>, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32);
typedef _GetParamC = Float Function(Pointer<Void>, Int32);
typedef _SetParamC = Int32 Function(Pointer<Void>, Int32, Float);

/// Wrapper around the dynamic library providing access to the C
/// functions. Users generally should not use this directly; instead
/// use the VstHost and VstPlugin classes in host.dart which manage
/// resources safely.
class NativeBindings {
  final DynamicLibrary lib;

  NativeBindings(this.lib);

  late final Pointer<Void> Function(double, int) dvhCreateHost =
      lib.lookupFunction<_HostCreateC, Pointer<Void> Function(double, int)>('dvh_create_host');

  late final void Function(Pointer<Void>) dvhDestroyHost =
      lib.lookupFunction<_HostDestroyC, void Function(Pointer<Void>)>('dvh_destroy_host');

  late final Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) dvhLoadPlugin =
      lib.lookupFunction<_LoadC, Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('dvh_load_plugin');

  late final void Function(Pointer<Void>) dvhUnloadPlugin =
      lib.lookupFunction<_UnloadC, void Function(Pointer<Void>)>('dvh_unload_plugin');

  late final int Function(Pointer<Void>, double, int) dvhResume =
      lib.lookupFunction<_ResumeC, int Function(Pointer<Void>, double, int)>('dvh_resume');

  late final int Function(Pointer<Void>) dvhSuspend =
      lib.lookupFunction<_SuspendC, int Function(Pointer<Void>)>('dvh_suspend');

  late final int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, int) dvhProcessStereoF32 =
      lib.lookupFunction<_ProcessStereoC, int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, int)>('dvh_process_stereo_f32');

  late final int Function(Pointer<Void>, int, int, double) dvhNoteOn =
      lib.lookupFunction<_NoteC, int Function(Pointer<Void>, int, int, double)>('dvh_note_on');

  late final int Function(Pointer<Void>, int, int, double) dvhNoteOff =
      lib.lookupFunction<_NoteC, int Function(Pointer<Void>, int, int, double)>('dvh_note_off');

  late final int Function(Pointer<Void>) dvhParamCount =
      lib.lookupFunction<_ParamCountC, int Function(Pointer<Void>)>('dvh_param_count');

  late final int Function(Pointer<Void>, int, Pointer<Int32>, Pointer<Utf8>, int, Pointer<Utf8>, int) dvhParamInfo =
      lib.lookupFunction<_ParamInfoC, int Function(Pointer<Void>, int, Pointer<Int32>, Pointer<Utf8>, int, Pointer<Utf8>, int)>('dvh_param_info');

  late final double Function(Pointer<Void>, int) dvhGetParam =
      lib.lookupFunction<_GetParamC, double Function(Pointer<Void>, int)>('dvh_get_param_normalized');

  late final int Function(Pointer<Void>, int, double) dvhSetParam =
      lib.lookupFunction<_SetParamC, int Function(Pointer<Void>, int, double)>('dvh_set_param_normalized');
}

/// Load the native library. The optional [path] may be used to point
/// directly at libdart_vst_host.{so,dylib,dll}. On platforms where
/// dynamic library lookup is provided by the process/executable, this
/// falls back accordingly.
DynamicLibrary loadDvh({String? path}) {
  if (path != null) return DynamicLibrary.open(path);
  if (Platform.isMacOS) return DynamicLibrary.open('libdart_vst_host.dylib');
  if (Platform.isLinux) return DynamicLibrary.open('libdart_vst_host.so');
  if (Platform.isWindows) return DynamicLibrary.open('dart_vst_host.dll');
  // Use process/executable fallback when available
  try {
    return DynamicLibrary.process();
  } catch (_) {}
  try {
    return DynamicLibrary.executable();
  } catch (_) {}
  throw UnsupportedError('Unable to locate native dart_vst_host library');
}