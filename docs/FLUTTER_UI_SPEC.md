# Plugin UI and DSP design

The VST3 module runs in the audio host process. Its editor embeds a Flutter engine in the host-provided native window (Cocoa on macOS, Win32 on Windows, GTK/X11 on Linux). The Flutter editor is not the audio processor.

DSP runs in a separate compiled Dart worker process for each plugin instance. The native processor exchanges audio blocks and parameter commands with that worker through shared memory and platform synchronization primitives. Audio is copied between the host buffers and shared memory; this is not zero-copy.

The controller connects Flutter parameter gestures to VST3 host automation. The editor reads the instance's shared-memory telemetry for visualization. Saved parameter state belongs to the VST3 processor and must be replayed to the worker when restoring a session. Closing an editor must not stop DSP; disposing a processor must release its worker and IPC resources.

Linux embedded editors require X11. Launch Flutter hosts with `GDK_BACKEND=x11 flutter run`; Wayland embedding is not supported.

Each requirement below has a spec ID, the code that implements it, and the test that proves it. `Test: none` means nothing proves it yet. Cite IDs in code and tests.

## Process model

### [PROCESS-ONE-WORKER-PER-INSTANCE]
Each `Vst3IpcHost` owns exactly one worker process, one shared block and two named semaphores; there is no shared pool of workers or blocks. Disposing one host MUST NOT disturb another host's worker or DSP state.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:85-98 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [PROCESS-WORKER-LAUNCH]
The constructor MUST NOT spawn anything; the worker starts on the first `configure()`. The executable is the sibling of the loaded module named `<plugin_id>_processor` (`.exe` appended on Windows), started with exactly four values: shm name, ready semaphore, done semaphore, host pid; the Dart entry point MUST reject any other argument count with `ArgumentError`.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:45-52,98 · Test: none

### [PROCESS-LIVE-RECONFIGURE]
`configure()` on a healthy running host MUST reuse the running worker: it reclaims the block, writes `sampleRate` and `maxBlockSize`, sends `VST3_CMD_CONFIGURE` and waits for the reply. The worker pid MUST be unchanged by that path.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:69-75 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [PROCESS-RESTART-ON-CONFIGURE]
A `configure()` after the worker died MUST dispose the remains and spawn a new worker; every previously known parameter value is marked dirty and pushed with the new worker's first block. The host MUST NOT restart a worker from `process()`.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:76-81,104 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

### [PROCESS-WORKER-EXITS-WITH-HOST]
The worker MUST spawn a watcher isolate that exits the process once the host pid is gone: POSIX polls `getppid()` every 250 ms, Windows waits on the host process handle. This MUST hold even when the host is killed without cleanup.
Code: flutter_vst3/lib/src/vst3_shared_memory_processor.dart:265-283 · Test: flutter_vst3/test/native/ipc_host_test.cpp

## Handshake

### [IPC-HANDSHAKE-START-SEQUENCE]
Startup MUST follow this order: unique names, map and zero the whole 69,632-byte block, write version/sampleRate/maxBlockSize/`VST3_CMD_IDLE`, write the magic word last, create both semaphores at zero, spawn, wait for the handshake, then unlink the names. The host MUST NOT set `running_` before the handshake reply arrives.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:85-101 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [IPC-HANDSHAKE-WORKER-ACK]
The worker MUST reject a block whose magic or version is wrong before touching DSP, then call `initialize(sampleRate, maxBlockSize)` from the block, then post the done semaphore. Startup completes for the host only when that post arrives.
Code: flutter_vst3/lib/src/vst3_worker_loop.dart:73-83 · Test: flutter_vst3/test/vst3_worker_loop_test.dart

### [IPC-HANDSHAKE-FAILURE]
Handshake and control waits MUST time out after 5000 ms, and a dead child MUST abort the wait immediately with "Dart worker exited". A throwing `configure()` MUST release everything, leaving `isRunning()` false, `workerProcessId()` 0 and `process()` silent.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:20,107-117 · Test: flutter_vst3/test/native/ipc_host_test.cpp

## Block layout

### [IPC-BLOCK-MAGIC]
A live block MUST hold `0x56535433` ("VST3") at offset 0 and protocol version `2` at offset 4; both are checked on both sides, and a wrong magic or version MUST NOT be treated as a usable block.
Code: flutter_vst3/native/include/vst3_shared_memory.h:23-26 · Test: flutter_vst3/test/vst3_shared_memory_test.dart

### [IPC-BLOCK-OFFSETS]
The block is exactly 69,632 bytes with page-aligned audio, little-endian, `#pragma pack(1)`, no atomic fields (non-atomic fields per owner process).
Code: flutter_vst3/native/include/vst3_shared_memory.h:42-58

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | `magic` (u32) |
| 4 | 4 | `version` (u32) |
| 8 | 8 | `sampleRate` (f64) |
| 16 | 4 | `maxBlockSize` (u32) |
| 20 | 4 | `command` (u32) |
| 24 | 4 | `numSamples` (i32) |
| 28 | 4 | `hostParamWriteIndex` (u32) |
| 32 | 4 | `hostParamReadIndex` (u32) |
| 36 | 1024 | `hostParams[64]` (16-byte events: id i32 @+0, padding i32 @+4, value f64 @+8) |
| 1060 | 4 | `uiParamWriteIndex` (u32) |
| 1064 | 4 | `uiParamReadIndex` (u32) |
| 1068 | 1024 | `uiParams[64]` |
| 2092 | 2004 | reserved padding to 4096 |
| 4096 | 16384 | `inputL[4096]` (f32) |
| 20480 | 16384 | `inputR[4096]` |
| 36864 | 16384 | `outputL[4096]` |
| 53248 | 16384 | `outputR[4096]` |

Test: flutter_vst3/test/vst3_shm_layout_test.dart

### [IPC-BLOCK-LAYOUT-MIRROR]
`flutter_vst3/lib/src/vst3_shm_layout.dart` MUST mirror the header's defines, and any change to a define MUST be made on both sides in the same commit. A test parses the header and fails on any value mismatch.
Code: flutter_vst3/lib/src/vst3_shm_layout.dart:8-68 · Test: flutter_vst3/test/vst3_shm_layout_test.dart

### [IPC-BLOCK-DEAD-MAGIC]
A block whose worker died or whose host was disposed MUST read magic 0 while its address stays mapped, so an in-process reader sees an invalid block instead of faulting. Readers MUST treat any non-magic value as "DSP not running".
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:194-200 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

## Commands and audio

### [IPC-COMMAND-DISPATCH]
The worker MUST read `command` at offset 20 on every handover, apply the matching action, and post done for every command except TERMINATE; an unknown or `IDLE` value MUST be a no-op that still posts done.
Code: flutter_vst3/lib/src/vst3_worker_loop.dart:114-131 · Test: flutter_vst3/test/vst3_worker_loop_test.dart

| Value | Command | Worker action |
| --- | --- | --- |
| 0 | `VST3_CMD_IDLE` | none |
| 1 | `VST3_CMD_PROCESS` | drain host ring, process `numSamples` |
| 2 | `VST3_CMD_TERMINATE` | leave the loop without posting done |
| 3 | `VST3_CMD_CONFIGURE` | re-read `sampleRate`/`maxBlockSize`, re-initialize |
| 4 | `VST3_CMD_RESET` | clear DSP state |

### [IPC-AUDIO-CHUNKING]
`process()` MUST split any length above `VST3_SHM_MAX_SAMPLES` (4096) into successive chunks of at most 4096 samples, each a separate handover, and MUST keep the overall result false if any chunk failed.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:243-250 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [IPC-AUDIO-COPY]
Per chunk the host MUST flush parameters, copy `numSamples` floats from both input channels into the block, write `numSamples` and `VST3_CMD_PROCESS`, hand over, then copy both output buffers back. Only stereo is supported: fewer than two input or output channels MUST produce silence.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:219-234 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [IPC-AUDIO-SILENCE-ON-FAILURE]
When any chunk is late or the worker is dead, the whole output buffer MUST be zeroed and `process()` MUST return false, so the caller's silence flags match every sample.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:215-218,249-250 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

## Synchronization

### [IPC-SYNC-HANDOFF]
Ownership passes only through the two semaphores: the host owns the block until it posts ready, the worker owns it until it posts done. While the previous block is unreclaimed the host MUST only try-wait and MUST leave the block byte-for-byte untouched.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:204-212 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

### [IPC-SYNC-PARAM-PUSH]
`setParameter()` MUST only record the value and mark it dirty; the queue MUST be written just before a handover, with 64-event capacity, and an event that does not fit MUST stay dirty for a later block. A later value for the same id MUST replace the earlier one.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:167-188 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

### [IPC-SYNC-PARAM-PULL]
The worker MUST drain the host ring at the start of each PROCESS block, apply events in order, and write the read index back; indices are 32-bit counters that wrap and MUST be masked, never clamped.
Code: flutter_vst3/lib/src/vst3_worker_loop.dart:188-204 · Test: flutter_vst3/test/vst3_worker_loop_test.dart

## Timeouts and worker death

### [IPC-TIMEOUT-BLOCK-BUDGET]
The wait for a processed block MUST be `max(1 ms, numSamples / sampleRate)`, except in offline mode where it is 30 s; control commands and the handshake use 5000 ms and termination allows a 500 ms grace before the child is killed.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:20-23,226 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

### [IPC-TIMEOUT-LATE-BLOCK]
On a missed deadline the host MUST mark the worker busy and return silence without any further wait, so subsequent blocks cost a try-wait only until the late done arrives. A late result MUST be discarded, never used for a later block.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:204-212,227-232 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

### [IPC-DEATH-DETECTION]
A child that is no longer alive MUST be forgotten with `isRunning()` false, `workerProcessId()` 0 and block magic 0. An exception escaping the DSP MUST print to stderr and exit the worker with code 70 so the host sees the death the same way.
Code: flutter_vst3/lib/src/vst3_worker_loop.dart:61,73-90 · Test: flutter_vst3/test/native/ipc_host_recovery_test.cpp

## Cleanup and leaks

### [IPC-CLEANUP-DISPOSE]
`dispose()` MUST post `VST3_CMD_TERMINATE` when the block and ready semaphore exist, wait up to 500 ms, then kill the child, close both semaphores, retire the mapping and clear running state. It MUST be safe to call repeatedly, including from the destructor before any configure.
Code: flutter_vst3/native/src/vst3_ipc_host.cpp:137-165 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [IPC-CLEANUP-RETIRED-BLOCK]
A retired block MUST stay mapped with magic 0 and be reused by the next `mapCreate()`; the retired pool is process-global, mutex-guarded and never destroyed. Total retained mapping is therefore bounded by the peak instance count, not by the number of configure/dispose cycles.
Code: flutter_vst3/native/src/vst3_ipc_retired.h:34-46 · Test: flutter_vst3/test/native/ipc_host_test.cpp

### [IPC-CLEANUP-SYSTEM-NAMES]
IPC names MUST be unique per instance and generation (`pid_owner_counter`, within macOS's 31-character limit), created exclusively at mode 0600, and unlinked once the worker has opened them so nothing outlives a host crash. The worker MUST close all inherited descriptors from 3 up before exec so no host handle leaks into it.
Code: flutter_vst3/native/src/vst3_ipc_platform_posix.cpp:36-44,90-92 · Test: flutter_vst3/test/native/ipc_platform_test.cpp

## Platform embedding

### [EDITOR-PLATFORM-TYPE]
`isPlatformTypeSupported` MUST return `kResultTrue` only for `kPlatformTypeNSView` on macOS, `kPlatformTypeHWND` on Windows and `kPlatformTypeX11EmbedWindowID` on Linux. `attached` MUST return `kInvalidArgument` for a null parent or any other type, before creating a window, an engine or a pending mount.
Code: flutter_vst3/native/src/embedded_flutter_view.cpp:106; flutter_vst3/native/src/embedded_flutter_view.mm:99 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-LINUX-X11-EMBED]
On Linux the editor MUST embed through `gtk_plug_new` on the host-supplied X11 window id, add the `FlView` to that plug, and map and raise the plug's XID. The plug MUST be realized and shown with a size request of 600x650 at mount.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:141 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-LINUX-X11-REQUIRED]
The Linux Flutter host MUST refuse to initialize unless `gtk_init_check` succeeds and the default display is a `GdkX11Display`; it forces allowed backends to `x11` only when no display exists and `GDK_BACKEND` is unset. When it refuses, `attached` MUST fall through to the GTK fallback host, which applies the same X11 check and returns `kResultFalse` if it also fails.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:49; flutter_vst3/native/src/embedded_flutter_view_linux_native.inc:25 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-COCOA-SUBVIEW]
On macOS the view MUST construct a `FlutterViewController` over the bundle's precompiled Dart bundle and add its view as a subview of the host `NSView`, sized to the parent bounds or 600x650 when those are degenerate. The subview MUST resize with the parent via `NSViewWidthSizable | NSViewHeightSizable`.
Code: flutter_vst3/native/src/embedded_flutter_view.mm:244 · Test: none

### [EDITOR-WIN32-HWND]
On Windows the view MUST create the desktop view controller at 600x650, clear `WS_POPUP` in favour of `WS_CHILD`, and `SetParent` the Flutter HWND into the host HWND. It MUST size that HWND to the parent client rect, falling back to 600x650, and force a redraw.
Code: flutter_vst3/native/src/embedded_flutter_view_win_flutter.inc:169 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-SIZE]
`getSize` MUST report 600x650 while a Flutter engine is mounted, and 540xmax(280, 74 + parameters*56 + 36) for the native fallback. After `onSize` it MUST report the last accepted rect and propagate that size to the plug, Flutter HWND or Flutter view. After a runtime Flutter failure the view MUST reset its cached size, mount the fallback and resize itself through `IPlugFrame::resizeView` to the fallback rect.
Code: flutter_vst3/native/src/embedded_flutter_view.cpp:166 · Test: flutter_vst3/test/native/editor_host_test.cpp

## Flutter app detection and native fallback

### [EDITOR-FLUTTER-DETECT-DESKTOP]
On Windows and Linux the Flutter app MUST be considered present only when the module directory has `data/flutter_assets` as a directory, `data/icudtl.dat` as a file, and an app library (`lib/libapp.so` or `libapp.so` on Linux, `data/app.so` or `flutter_assets/kernel_blob.bin` on Windows). Windows additionally MUST load `flutter_windows.dll` from the module directory before mounting.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:35; flutter_vst3/native/src/embedded_flutter_view_win_flutter.inc:63 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-FLUTTER-DETECT-COCOA]
On macOS the Flutter app MUST be considered present only when `Contents/Frameworks` holds `App.framework/App`, `App.framework/Resources/flutter_assets` and `FlutterMacOS.framework/Resources/icudtl.dat`, and the build MUST define `VST3_FLUTTER_ENTRYPOINT`. Otherwise the view MUST mount the Cocoa fallback without attempting to load any framework.
Code: flutter_vst3/native/src/embedded_flutter_view.mm:36 · Test: none

### [EDITOR-CORRUPT-APP-COCOA]
macOS MUST `dlopen` the App framework executable and reject it before constructing a view, because a corrupt app library crashes the host. A mount exception or an engine that will not run MUST remove the subview, shut the engine down, nil the channel and fall back to the Cocoa sliders.
Code: flutter_vst3/native/src/embedded_flutter_view.mm:66 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-FALLBACK-NATIVE-ROWS]
The fallback MUST build one row per controller parameter with a name label, a value label rendered from `getParamStringByValue`, and a 0..1 slider (Cocoa `NSSlider`, GTK `GtkScale`, Win32 trackbar). Each row's control MUST begin an edit on gesture start, set and perform on change, and end the edit on release.
Code: flutter_vst3/native/src/native_cocoa_view.mm:101; flutter_vst3/native/src/embedded_flutter_view_linux_native.inc:118 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-START-WATCHDOG]
A mount MUST arm a 10000 ms watchdog; if the controller still owns the editor and the Dart side has made no channel call, or engine creation failed, the Flutter host MUST tear itself down and the view MUST mount the native fallback.
Code: flutter_vst3/native/include/view_logic.h:12; flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:175 · Test: flutter_vst3/test/native/view_logic_test.cpp; flutter_vst3/test/native/editor_host_test.cpp

## Editor lifecycle

### [EDITOR-SINGLE-FLUTTER-OWNER]
At most one Flutter editor per module process MAY exist: a second view MUST be refused a Flutter host and MUST mount the 540-wide native fallback. It MUST NOT take over the existing plug, engine or channel, and closing the non-owner MUST NOT disturb the owner's editor.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:48; flutter_vst3/native/src/embedded_flutter_view_win_flutter.inc:75; flutter_vst3/native/src/embedded_flutter_view.mm:107 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-DEFERRED-MOUNT]
Engine creation MUST be deferred out of `attached`: a 50 ms GLib timeout on Linux, a 10 ms Win32 timer on Windows, and `dispatch_async` on the macOS main queue. The deferred mount MUST re-check that the editor still owns the controller and, on macOS, that the parent view is unchanged, and MUST be cancellable by closing the editor first.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:63; flutter_vst3/native/src/embedded_flutter_view_win_flutter.inc:100; flutter_vst3/native/src/embedded_flutter_view.mm:112 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-LIVENESS-TOKEN]
On macOS every queued UI action — parameter updates, fallback label refresh and method calls — MUST run only when the editor's liveness token is still set. Closing the editor MUST clear the token so work already queued is dropped instead of touching a torn-down view.
Code: flutter_vst3/native/include/view_logic.h:8; flutter_vst3/native/src/embedded_flutter_view.mm:159 · Test: flutter_vst3/test/native/editor_liveness_test.cpp; flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-CLOSE-ENDS-EDITS]
`removed` MUST end any gesture still open on the controller before tearing the UI down. A release that arrives after the editor closed MUST NOT be able to reopen or extend that gesture.
Code: flutter_vst3/native/src/embedded_flutter_view.cpp:160; flutter_vst3/native/src/embedded_flutter_view.mm:121 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-CLOSE-KEEPS-ENGINE]
Closing a mounted Flutter editor MUST only notify `onHostDetached`, hide the view and detach it from the host window — reparenting to the root window on Linux and to a hidden holder window on Windows — and MUST NOT destroy the engine or the channel. Only a startup failure MAY destroy the engine and plug.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:297; flutter_vst3/native/src/embedded_flutter_view_win_flutter.inc:206 · Test: flutter_vst3/test/native/editor_host_test.cpp

### [EDITOR-REOPEN-RESYNC]
Reopening MUST re-embed the surviving plug/view into the new parent window and resize it, then invoke `onHostAttached` and push every parameter's current normalized value to Dart before any user input. A view reattached after being closed MUST choose Flutter again when it is eligible, not keep the stale native size.
Code: flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:234; flutter_vst3/native/src/embedded_flutter_view_win_flutter.inc:177 · Test: flutter_vst3/test/native/editor_host_test.cpp

## Telemetry

### [TELEMETRY-SHM-INFO]
`getSharedMemoryInfo` MUST reply with `address` taken from that instance's controller, plus `totalSize` and `maxSamples` as the shared-memory constants, and MUST reply 0 for the address when the controller has no block. The reply MUST be per instance, never a process-global block.
Code: flutter_vst3/native/src/embedded_flutter_view.mm:309; flutter_vst3/native/src/embedded_flutter_view_linux_flutter.inc:121 · Test: vsts/echo/test/ui_regression_test.dart

### [TELEMETRY-READER-MAGIC]
A reader MUST be created only when the address is non-zero and the first 32-bit word of the block equals `vst3ShmMagic`; otherwise the result MUST be null. `isValid` MUST re-read the magic on every check.
Code: flutter_vst3/lib/src/shared_memory_reader.dart:32 · Test: flutter_vst3/test/shared_memory_reader_test.dart

### [TELEMETRY-DSP-STOPPED-FLAG]
Each reader fetch MUST set `dspStopped` to true only when the address is non-zero and the reader came back null, and MUST notify listeners only when the flag changes. A zero address MUST read as deactivated, not stopped, and a failed fetch MUST leave the flag unchanged.
Code: flutter_vst3/lib/src/parameter_binding.dart:238 · Test: flutter_vst3/test/dsp_stopped_test.dart

### [TELEMETRY-DSP-STOPPED-MESSAGE]
Echo's editor MUST show the text "DSP stopped. Audio is silent until the plugin is re-enabled." exactly while `dspStopped` is true, and MUST remove it when a fetch succeeds again.
Code: vsts/echo/lib/ui/echo_ui.dart:125 · Test: vsts/echo/test/ui_regression_test.dart

### [TELEMETRY-RESTART-POLL]
The waveform visualiser MUST poll every 33 ms and MUST do nothing while the host is detached. An invalid reader MUST be dropped and refetched immediately; a missing reader MUST trigger a refetch only when `dspStopped` is set, at most once per 30 ticks.
Code: vsts/echo/lib/ui/echo_ui.dart:181; vsts/echo/lib/ui/echo_ui.dart:219 · Test: vsts/echo/test/ui_regression_test.dart

### [TELEMETRY-DETACH]
`onHostDetached` MUST set `isHostAttached` false, drop the cached reader and clear pending begins before notifying listeners. `onHostAttached` MUST set it true, drop the reader and reload the initial parameter map.
Code: flutter_vst3/lib/src/parameter_binding.dart:58 · Test: vsts/echo/test/ui_regression_test.dart

### [TELEMETRY-BOUNDS]
`numSamples` MUST be clamped to 0..`vst3ShmMaxSamples`, and every typed-list accessor MUST return an empty list when the block is invalid. `getLatestOutputSamples` MUST return a mono average of output L and R, capped by `maxCount` and the shared-memory maximum, as a copy rather than a view.
Code: flutter_vst3/lib/src/shared_memory_reader.dart:50; flutter_vst3/lib/src/shared_memory_reader.dart:91 · Test: flutter_vst3/test/shared_memory_reader_test.dart

## Parameter gestures and values

### [PARAM-GESTURE-DEFERRED]
`beginEdit` MUST only add the id to a local pending set; it MUST NOT send anything over the `flutter_vst3/parameters` channel.
Code: flutter_vst3/lib/src/parameter_binding.dart:176 · Test: flutter_vst3/test/parameter_binding_contract_test.dart

### [PARAM-GESTURE-VALUE-OPENS]
The first `setParameter` for a pending id MUST send `beginEdit` with `{'id': id}` before sending `setParameter` with `{'id': id, 'value': clamped}`, so a tap that never changes a value leaves no host gesture.
Code: flutter_vst3/lib/src/parameter_binding.dart:196 · Test: flutter_vst3/test/parameter_binding_contract_test.dart

### [PARAM-GESTURE-END]
`endEdit` MUST send `endEdit` with `{'id': id}` only when the id is no longer pending, and MUST send nothing when the gesture never reached the host.
Code: flutter_vst3/lib/src/parameter_binding.dart:179 · Test: flutter_vst3/test/parameter_binding_contract_test.dart

### [PARAM-VALUE-CLAMP]
`setParameter` MUST clamp the value to 0.0..1.0, MUST store the clamped value in the local cache before sending, and MUST notify listeners afterwards.
Code: flutter_vst3/lib/src/parameter_binding.dart:193 · Test: flutter_vst3/test/parameter_binding_contract_test.dart

### [PARAM-INBOUND-VALIDATION]
An inbound `onParameterChanged` message MUST carry an int id in `0..parameterCount-1` and a finite value in 0.0..1.0; any other id, value or argument shape MUST raise `ArgumentError` and MUST leave the cache unchanged.
Code: flutter_vst3/lib/src/parameter_binding.dart:119 · Test: flutter_vst3/test/parameter_binding_contract_test.dart

### [PARAM-INITIAL-LOAD]
`loadInitialParameters` MUST accept only a map whose keys are ints or decimal-digit strings and whose values pass the same range check, and MUST apply all of that map or none of it. `MissingPluginException` MUST be ignored, leaving the cache untouched.
Code: flutter_vst3/lib/src/parameter_binding.dart:79 · Test: flutter_vst3/test/parameter_binding_contract_test.dart

### [PARAM-PERFORM-GESTURE]
A UI value MUST be applied to the controller as `setParamNormalized` followed by `performEdit`. `beginEdit` MUST reach the host only on the first begin for an id, and `performEdit` MUST return `kResultFalse` when no gesture is open for that id.
Code: flutter_vst3/native/templates/plugin_controller.cpp.template:91 · Test: flutter_vst3/test/native/view_logic_test.cpp

### [PARAM-ECHO-SUPPRESSED]
`setParamNormalized` MUST forward a host value to the active view only when that id is not mid-gesture, and `isEditing` MUST report the inverse, so a UI never receives its own drag echoed back.
Code: flutter_vst3/native/templates/plugin_controller.cpp.template:54 · Test: flutter_vst3/test/native/view_logic_test.cpp

### [PARAM-AUTOMATION-PER-BLOCK]
The processor MUST apply host automation once per block, using only the last point of each parameter queue, MUST ignore ids at or above the parameter count, and MUST pass accepted values to the worker through `Vst3IpcHost::setParameter`.
Code: flutter_vst3/native/templates/plugin_processor_aot.cpp.template:159 · Test: flutter_vst3/test/native/plugin_host_test.cpp

## Saved state

### [STATE-LAYOUT]
Saved state MUST be the parameter count times 8 bytes of IEEE-754 doubles in ascending parameter id, with no header, magic, version or count field.

| Offset | Size | Contents |
| --- | --- | --- |
| 0 | 8 | normalized value, parameter 0 |
| 8 | 8 | normalized value, parameter 1 |
| 8×n | 8 | normalized value, parameter n |

Code: flutter_vst3/native/include/vst3_plugin_state.h:14 · Test: flutter_vst3/test/native/plugin_host_test.cpp

### [STATE-READ-REJECT]
Reading MUST return false when the stream supplies fewer than 8 bytes for any value, or a value that is not finite or is outside 0.0..1.0. A failed read MUST leave the caller's vector unchanged so a state is applied whole or not at all.
Code: flutter_vst3/native/include/vst3_plugin_state.h:22 · Test: flutter_vst3/test/native/plugin_host_test.cpp

### [STATE-PROCESSOR-IO]
`setState` MUST return `kResultFalse` and change no parameter when the read fails, and MUST mark the state dirty on success. `getState` MUST return `kResultFalse` when the stream takes fewer than 8 bytes for a value.
Code: flutter_vst3/native/templates/plugin_processor_aot.cpp.template:204 · Test: flutter_vst3/test/native/plugin_host_test.cpp

### [STATE-CONTROLLER-SET-STATE]
Controller `setComponentState` and `setState` MUST use the same reader and apply values through `setParamNormalized`; a rejected state MUST leave every parameter as it was. Controller `getState` MUST write the current normalized values in id order.
Code: flutter_vst3/native/templates/plugin_controller.cpp.template:107 · Test: flutter_vst3/test/native/plugin_host_test.cpp

### [STATE-REPLAY-DEFERRED]
`setState` MUST NOT talk to the worker; it MUST only mark the state dirty, and the next `process` call MUST push every parameter value to the worker before that block's automation. A restarted worker MUST receive the known values again.
Code: flutter_vst3/native/templates/plugin_processor_aot.cpp.template:176 · Test: flutter_vst3/test/native/plugin_host_test.cpp

## Lifecycle

### [LIFECYCLE-SET-ACTIVE-START]
`setActive(true)` MUST configure the worker with the sample rate, block size and offline flag from `setupProcessing`, mark the state dirty, and send the worker's memory address to the controller. A worker that fails to start MUST make `setActive` return `kResultFalse` rather than throw.
Code: flutter_vst3/native/templates/plugin_processor_aot.cpp.template:123 · Test: flutter_vst3/test/native/plugin_host_test.cpp

### [LIFECYCLE-SET-ACTIVE-STOP]
`setActive(false)` MUST send address 0 to the controller and reset the worker's DSP state; it MUST NOT stop or dispose the worker.
Code: flutter_vst3/native/templates/plugin_processor_aot.cpp.template:130 · Test: flutter_vst3/test/native/plugin_host_test.cpp

### [LIFECYCLE-PROCESS-NOT-ACTIVE]
`process` MUST silence every output bus and return `kNotInitialized` when there is no IPC host or the last `setActive` did not succeed.
Code: flutter_vst3/native/templates/plugin_processor_aot.cpp.template:183 · Test: flutter_vst3/test/native/plugin_host_test.cpp

## Build generation

### [BUILD-GENERATED-SOURCES]
The build MUST generate `<target>_controller.cpp`, `<target>_processor.cpp` and `<target>_factory.cpp` from the three templates, plus `<target>_ids.h` and `metadata.cmake`, into the build directory's `generated` folder. Any unresolved `{{...}}` placeholder MUST abort generation.
Code: flutter_vst3/scripts/generate_plugin.dart:88 · Test: flutter_vst3/test/generate_plugin_test.dart

### [BUILD-WORKER-EXE]
The build MUST compile `lib/<target>_processor_exe.dart` with `dart compile exe` at configure time and MUST fail configuration when that source is missing or the compile returns non-zero.
Code: flutter_vst3/native/cmake/VST3Bridge.cmake:129 · Test: none

### [BUILD-PARAMETER-IDS]
Metadata parameter ids MUST be exactly 0..n-1 in order, and every parameter name MUST reduce to a unique C identifier used for its enum entry and display title.
Code: flutter_vst3/scripts/generate_plugin.dart:216 · Test: flutter_vst3/test/generate_plugin_test.dart

### [BUILD-METADATA-REJECT]
Generation MUST exit non-zero on any invalid metadata, including the cases in the table below. Accepted text MUST have backslashes, quotes and newlines escaped when copied into C++ string literals and CMake values.

| Rejected input | Reason recorded |
| --- | --- |
| missing `pluginName`/`vendor`/`version`/`category`/`bundleIdentifier`/`companyWeb`/`companyEmail` | required field |
| parameter `defaultValue` not a finite number in 0..1 | invalid parameter default |
| parameter name reducing to an already used identifier | duplicate parameter identifier |
| name or value not convertible to `[A-Za-z][A-Za-z0-9]*` | unusable identifier |
| text containing control characters | expected text without control characters |
| `processorUid`/`controllerUid` set singly, equal, or not 32 hex digits | must be set together / must differ / 32 hex digits |

Code: flutter_vst3/scripts/generate_plugin.dart:282 · Test: flutter_vst3/test/native/generator_strings_test.py

## Gaps

Where the code falls short of this design or lacks a test. Nothing here is fixed yet.

- The intro says disposing a processor releases its IPC resources, but the mapping is retired, not released: each peak instance retains 69,632 bytes plus its platform handle for the life of the host process.
- The layout declares a UI-to-host parameter ring (`uiParamWriteIndex`/`uiParamReadIndex`/`uiParams` at 1060/1064/1068) that no code reads or writes today; the editor's only shared-memory use is the block address message plus magic-based validity checks.
- `vst3_shm_layout.dart` has no constants for the UI-ring offsets; `vst3_shm_layout_test.dart` compares those three defines against hardcoded literals instead, so they are not actually mirrored.
- After a worker dies nothing restarts it automatically: the template keeps `active_` true and `process()` keeps returning `kResultOk` with silence flags, so the plugin stays silent until the host deactivates and reactivates.
- `vst3_ipc_host.h` claims `process` "never waits longer than the block's own duration", but the budget floor is 1 ms and macOS polls the done semaphore in 50 µs sleeps.
- The `command` field comment in `vst3_shared_memory.h` lists only PROCESS and TERMINATE, while IDLE, CONFIGURE and RESET are also written.
- `shared_memory_reader.dart` validates only the magic word, not the protocol version, so a block from another protocol version would read as valid.
- No test pins the 5000 ms handshake/control timeout or the 500 ms terminate grace; no test asserts the worker's exit code 70 for a DSP exception, only that the host notices the death.
- macOS never invokes `onHostAttached` or `onHostDetached` (only Linux `embedded_flutter_view_linux_flutter.inc:234,305` and Windows `embedded_flutter_view_win_flutter.inc:177,216` do), so on macOS the Dart `isHostAttached` stays at its initial `true`, the cached reader is never dropped on close and no test covers telemetry after a macOS close/reopen.
- `getSize` can report the Flutter 600x650 before `attached` for a view that will then mount the 540-wide native fallback, because `hasFlutter_` is set in the constructor (`embedded_flutter_view.cpp:70`, `embedded_flutter_view.mm:83`) without the ownership check used at attach time. No test calls `getSize` before `attached`.
- On Linux, a non-X11 display makes both the Flutter host and the GTK fallback initialise nothing, so `attached` returns `kResultFalse` and no editor appears at all; the spec prose only says Wayland embedding is unsupported, and this path is untested.
- The startup watchdog treats "no method-channel call within 10 s" as a dead UI, so a working Flutter editor that never calls `flutter_vst3/parameters` would be replaced by native sliders. No test covers that case.
- `withLiveEditor` is used only by macOS; the Windows and Linux views gate queued work on controller identity alone, and `editor_liveness_test.cpp` tests the helper rather than any view.
- `dspStopped` is not cleared by `onHostDetached` (`parameter_binding.dart:58`), so the "DSP stopped" message would persist through a detach; no test covers detach while stopped.
- The "DSP stopped" text exists only in the Echo example UI; `flutter_vst3` itself ships no widget or message for it, so the requirement is example-level, not library-level.
- The generator emits `{{GET_PARAMETER_INFO}}`, `{{PARAMETER_STATE_SAVE}}`, `{{PARAMETER_STATE_LOAD}}`, `{{NORMALIZE_PARAMETER}}` and `{{DENORMALIZE_PARAMETER}}` snippets that no template consumes, so per-parameter min/max and Dart-side text conversion never reach C++; parameter text uses the SDK `EditController` defaults (generate_plugin.dart:128-173 versus native/templates).
- `VST3ParameterHandler` and `VST3ParameterInfo` are exported from `flutter_vst3.dart` but nothing in the bridge, generator or plugins uses them.
- Host automation values are stored and forwarded to the worker without the finite/0..1 check that saved state gets, so an out-of-range automation value reaches the DSP (plugin_processor_aot.cpp.template:159).
- The state reader never checks for trailing bytes, so a stream holding more than the parameter count is accepted (vst3_plugin_state.h:14); no test covers this.
- No test asserts that closing an editor leaves the worker running; `immediateClose` only checks that a closing editor does not change a parameter value (editor_host_regressions.h:51).
- `performEdit`/`endEdit` return codes and the echo suppression on `setParamNormalized` are only covered at the `EditState` level (view_logic_test.cpp), never through the controller.
- The platform channel handlers report success to Flutter for `beginEdit`/`endEdit` even when the controller rejects the gesture (`kResultFalse`), so the failure is invisible to Dart (embedded_flutter_view.mm:321).
- `VST3ParameterBinding.getInstance` fixes `parameterCount` at 64 on first use, so a plugin with more parameters would reject its own ids; no test covers a count above the default.
