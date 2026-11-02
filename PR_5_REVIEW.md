# Review: PR #5, shared-memory DSP and embedded Flutter GUI

| | |
|---|---|
| PR | [#5](https://github.com/MelbourneDeveloper/flutter_vst3/pull/5), `alnitak:fromSoloud` at `d152d9e` |
| Merged to | `feature/soloud-shared-memory-gui` as `63b646d` (not `main`) |
| Diff reviewed | `main` (`39d5e42`) to `63b646d`: 26 commits, 119 files |
| Line numbers | All `file:line` references are at `63b646d` |
| Verdict | Every blocker is closed, and CI passes on all three OSes. Not tried in a real DAW: see [limits](#what-this-does-not-prove) |

Status values: `Fixed` (a test proves it, and was seen to fail when the fix was undone; the [fix log](#fix-log) names it),
`Won't fix` (reason given).

## Summary

The separate-process DSP design is sound. It isolates Dart from the host's audio thread and keeps the Flutter engine out
of the DSP process. The implementation isn't ready: one late block desynchronizes audio for the rest of the session, two
instances of one plugin share one DSP, the sample rate never reaches the DSP, saved state never reaches the DSP, and every
Windows editor with parameters can deadlock on open. The PR's test claims don't hold up: its one new test file covers
argument checks and a bad magic number, and `make test` can't fail for three of its packages.

## Blockers

### IPC and audio path

Paths are under `flutter_vst3/native/templates/` unless given in full. `native` is `plugin_processor_native.cpp.template`
and `aot` is `plugin_processor_aot.cpp.template`.

| ID | Where | Trigger | Failure | Required fix | Proof required | Status |
|---|---|---|---|---|---|---|
| B1 | `native:269-299` | One block takes over 50 ms, such as a Dart GC pause or a scheduler stall | The late `sem_done` stays posted, so the next block takes it at once and copies the previous output. The host then overwrites input while the worker is reading it. It never recovers | The host owns shared memory only between "done" and "ready". After a timeout it leaves shared memory alone, outputs silence, and resyncs when the late "done" arrives | Round trip with a real worker: stall one block, then assert later blocks return their own output | Fixed |
| B2 | `aot:83,106-109` | Host runs at anything but 44.1 kHz, or changes rate or block size | `setupProcessing` stores the rate, but `initialize` returns early when already set up (`native:119`), and block size is hardcoded to `512`. A second activation at a new rate leaves the DSP on the old one, so delay times are wrong | Pass `setup.sampleRate` and `setup.maxSamplesPerBlock`, and reconfigure the live worker on activation | Activate at 44.1k, reactivate at 96k, assert the worker sees 96k | Fixed |
| B3 | `native:404-411`, `aot:82-84` | Worker missing, or handshake fails | `native_initialize` swallows the exception, the caller sets `nativeProcessorInitialized = true`, and the plugin is silent with no error. The `catch`/`abort` in `aot` is unreachable. Shared memory, semaphores and the child leak | Roll back all resources on failure and return failure from `setActive` | Missing exe and exe that exits at once: both fail fast, leaving no child, shm or semaphores | Fixed |
| B4 | `native:262,293-299` | Block larger than 4096 samples, such as offline render | Only the first 4096 samples are processed. Samples past that in `output` are never written, so the host plays stale memory | Process in chunks of up to 4096 samples | 10000-sample block matches the same audio in small blocks | Fixed |
| B5 | `native:401,406` | Two instances of one plugin in a session | `g_processor` is per module. Both instances share one DSP and one parameter set, and audio passes through a single delay line. Disposing either kills both | One host object per plugin instance | Two instances keep separate DSP state, and disposing one leaves the other working | Fixed |
| B6 | `aot:181-197` | Save and reload a project | `getState`/`setState` use C++ member doubles that `process()` never updates, and nothing forwards them to Dart. Saved projects restore defaults | Track values in `process()`, and replay state to the worker before audio starts | Automate, get state, load into a new instance, assert the DSP received the values | Fixed |
| B7 | `native:261,269-291`, `native:303-315` | Every block | Audio thread holds a mutex, sleeps in a poll loop, and can block for 50 ms against a block budget of a few ms. A full parameter ring drops automation | No mutex or fixed 50 ms wait. Base the budget on block length with a real timed wait, and keep the latest value when the ring is full | Timing test: stalled worker costs at most one budget. Overflow test: the last value arrives | Fixed |
| B8 | `native:223-235` | Worker dies mid-session | Every later block stalls 50 ms and outputs silence, and the host's audio thread runs far behind. On Linux, `PR_SET_PDEATHSIG` also fires when the *spawning thread* exits, so the worker can die while the DAW lives. Other platforms orphan the worker if the host dies | Detect a dead child and skip the wait. Have the worker watch the host process directly | Kill the worker: later blocks return silence immediately. Kill the host: the worker exits | Fixed |
| B9 | `native:328` | Windows: two instances, editor open on A, delete B | `UnmapViewOfFile` frees memory the UI reader still reads, so the host crashes. POSIX is safe through the `MAP_FIXED` remap | Keep the Windows view mapped with `magic = 0`, and reuse it | Reader stays valid and reads `isValid == false` after dispose on both OSes | Fixed |
| B10 | `native:317`, `aot:94-96` | Stop transport, or `setActive(false)` | `reset()` is an empty body, so old tails play on restart | Add a reset command that reaches the DSP | Reset clears an echo tail in a round trip | Fixed |

### Embedded GUI

Paths are under `flutter_vst3/native/src/`.

| ID | Where | Trigger | Failure | Required fix | Proof required | Status |
|---|---|---|---|---|---|---|
| B11 | `embedded_flutter_view.cpp:146,227,262` | Windows: open an editor on a plugin with parameters | `mount` holds a non-recursive `std::mutex`, calls `updateParam`, which locks it again. That's undefined behaviour and in practice a deadlock or abort | Split into locked and unlocked functions | Windows compile plus a test on the extracted logic | Fixed |
| B12 | `embedded_flutter_view.cpp:156,168` | Any plugin other than Echo on Windows and Linux | Entrypoint is hardcoded to `"echoMain"`. Reverb's editor can't start | Take the entrypoint from `plugin_metadata.json` and pass it as a compile definition | Generator test: the entrypoint reaches CMake metadata | Fixed |
| B13 | `embedded_flutter_view.cpp:247-268,891-913` | Two editors open, close one | `sActiveController` is cleared unconditionally and `updateParam` has no instance check. Editor B drives A's parameters and closing A blanks B | Check ownership on shutdown and update | Test of the extracted ownership logic | Fixed |
| B14 | `embedded_flutter_view.cpp:1216,1228,1231` | Flutter engine fails to start | `attached` ignores the failure and returns `kResultTrue`, leaving a blank editor. The PR claims a graceful fallback | Return failure, or mount the native sliders that already exist | Force init failure: native UI appears or `attached` fails | Fixed |

## High

| ID | Where | Problem | Fix | Status |
|---|---|---|---|---|
| H1 | `flutter_vst3/lib/src/vst3_shared_memory_processor.dart:339-349` | `readIdx++` is an unbounded Dart int but `writeIdx` is `Uint32`. At the 2^32 wrap, `readIdx != writeIdx` never ends and the worker hangs | Mask to 32 bits, with a wrap test | Fixed |
| H2 | same file `:165-172` | `mmap` is compared with `nullptr`, not `MAP_FAILED`. `sem_open` results aren't checked, so a failure segfaults later | Check both and throw | Fixed |
| H3 | same file, plus `vst3_shared_memory.h` | Layout constants are hand-copied in Dart, `version` is never validated, and C++ has no `static_assert` | `static_assert` in C++, a test parsing the header against Dart constants, and a version check | Fixed |
| H4 | `native:123,195,217-218` | Names use only 16 bits of `this`. On Windows, a collision opens the existing mapping and `memset`s another instance's audio. Mode `0666` lets any local user read or inject audio | Full pointer in the name, exclusive creation, mode `0600` | Fixed |
| H5 | `native:166` | `CreateProcessA` flags are `0`, so a console window pops up with each instance on Windows | `CREATE_NO_WINDOW` | Fixed |
| H6 | `native:234` | `exit(1)` after `fork` runs host static destructors in the child | `_exit` | Fixed |
| H7 | `flutter_vst3/native/src/vst3_shared_memory.cpp:7-15` | Process-global "active shm": last writer wins, so editor A shows instance B's waveform. Closing either instance nulls it for both | Route the address from processor to controller over `IConnectionPoint` | Fixed |
| H8 | `flutter_vst3/lib/src/shared_memory_reader.dart:46-54,124-139` | `try/catch` around a raw pointer deref can't catch a segfault. `numSamples` isn't clamped | Rely on B9 for validity, remove the catch, clamp | Fixed |
| H9 | `flutter_vst3/lib/src/flutter_vst3_bridge.dart:44-56` | `registerProcessor` now always throws, but `vsts/echo/lib/src/echo_bridge.dart:14` calls it and `flutter_vst3/README.md:60` documents it. The export of `flutter_vst3_callbacks.dart` was removed without a changelog entry | Remove the stale API, caller and docs, or restore it | Fixed |
| H10 | `embedded_flutter_view.cpp:307-310,764-767`, `:510-513,1059-1062`, `embedded_flutter_view.mm:240-243`, `native_cocoa_view.mm:22-25` | Each drag tick sends begin, perform and end, so a single gesture becomes hundreds of automation undo steps | One begin and end per gesture, with channel methods for Dart | Fixed |
| H11 | `plugin_controller.cpp.template:44-50` | `setParamNormalized` echoes the UI's own edits back, so sliders jitter during a drag | Skip the echo while the parameter is being edited | Fixed |
| H12 | `embedded_flutter_view.cpp:128` | `SetDllDirectoryW` changes host-wide DLL search and is never restored | Restore it, or use `LoadLibraryExW` with full paths | Fixed |
| H13 | `embedded_flutter_view.cpp:710-712,949-950` | `setenv("GDK_BACKEND")` and `gdk_set_allowed_backends` change the whole host process | Skip when GTK is already initialized, and document the X11 requirement | Fixed |
| H14 | `embedded_flutter_view.cpp:397-423` | A fixed window class name registers under the host `hInstance` with this DLL's `wndProc`. A second plugin gets the first plugin's window procedure, which is a crash once that module unloads | Use a per-module class name and the module's own `HINSTANCE` | Fixed |
| H15 | `embedded_flutter_view.mm:85-89,230-233` | `dispatch_async` captures raw `this`, and `weakCtrl` is a raw pointer, so it's use-after-free if the view closes first | Liveness token checked in the block | Fixed |
| H16 | `embedded_flutter_view.mm:49-51`, `native_cocoa_view.h:10-14` | Flutter framework class lookups are process-wide. Objective-C classes in embedded view code can collide between plugins | Per-plugin class prefix everywhere | Fixed for our classes. Won't fix for Flutter's (see fix log) |
| H17 | `flutter_vst3/native/cmake/VST3Bridge.cmake:44-45` | The Steinberg validator is turned off | Turn it on and run it in CI | Fixed |
| H18 | `VST3Bridge.cmake:385-387,420-422,450-452` | Release builds silently fall back to the Debug Flutter bundle | `FATAL_ERROR` | Fixed |
| H19 | `VST3Bridge.cmake:314-316` | Windows and Linux silently drop the embedded GUI when `ephemeral` is absent at configure time. No `$ORIGIN` RPATH was found for `libflutter_linux_gtk.so` | Fail or say so with `message(STATUS)`, and set the RPATH | Fixed |
| H20 | `vsts/flutter_reverb/lib/src/reverb_processor.dart:139-142` | `processStereo` returns silently when uninitialized or on a length mismatch, leaving output unwritten. Breaks the repo's fail-hard rule | Throw, as Echo does | Fixed |
| H21 | `vsts/echo/lib/src/echo_processor.dart:93-96` | Bypass doesn't feed the delay line or advance the write index, so unbypassing replays a frozen tail | Keep the delay line running during bypass | Fixed |
| H22 | `vsts/echo/lib/src/echo_processor.dart:7,98` | Delay is 10-500 ms but docs and metadata say 0-1000 ms. The fixed 132300-sample buffer also clamps delay at high rates | Match the docs and size the buffer from the sample rate | Fixed |
| H23 | `vsts/echo/lib/src/echo_processor.dart:125-128` | `_softSaturate` jumps from 1.0 to 0.5 at the threshold, which adds a click in the feedback path | Continuous curve, with a test | Fixed |
| H24 | `vsts/echo/lib/ui/echo_ui.dart:56` | Shows `value*100` with the units, so "50.0ms" appears for a real delay of about 255 ms | Format from each parameter's real range | Fixed |

## Medium and low

| ID | Where | Problem | Status |
|---|---|---|---|
| M1 | `flutter_vst3/lib/src/parameter_binding.dart:48-55,81,178` | `print` debugging and `catch (_) {}` hide failures | Fixed |
| M2 | `parameter_binding.dart:189-224` | Dead `VST3AudioProcessor` class describing the rejected same-isolate design | Fixed |
| M3 | `vsts/echo/lib/src/echo_processor.dart:114-122` | `waveformBuffer` is unreachable because the UI runs in another process, and it costs CPU each block | Fixed |
| M4 | `vsts/echo/lib/ui/echo_ui.dart:2` | Comment claims the UI shares a process with the DSP | Fixed |
| M5 | `vsts/echo/lib/ui/echo_ui.dart:198,206,219` | Forces a channel call on every parameter change, and every 33 ms when there is no reader | Fixed |
| M6 | `vsts/echo/lib/ui/echo_ui.dart:307` | Divides by zero with a single sample | Fixed |
| M7 | `vsts/echo/lib/ui/echo_ui.dart:91,95`, `pubspec.yaml` | Uses `withValues` and `activeThumbColor` while pubspecs allow Flutter `>=3.0.0` | Fixed |
| M8 | `flutter_vst3/native/src/flutter_embedder.cpp`, `flutter_embedder_stubs.cpp`, `include/flutter_embedder.h` | Unbuilt code. The first defines `class FlutterEmbedder` twice and can't compile, and the stubs return fake handles such as `0x1234` | Fixed |
| M9 | `flutter_vst3/native/src/plugin_view.cpp:86` | Unbuilt, and runs `system()` with a hardcoded `/Users/christianfindlay/...` path | Fixed |
| M10 | `vsts/echo/echo_processor` | 5.6 MB committed Mach-O binary | Fixed |
| M11 | `vsts/echo/macos/Flutter/ephemeral/*`, `.vscode/settings.json` | Machine-specific paths committed | Fixed |
| M12 | `vsts/echo/README.md` | Flutter template boilerplate | Fixed |
| M13 | `FLUTTER_UI_SPEC.md` | Calls same-isolate UI "non-negotiable", which the implementation contradicts | Fixed |
| M14 | `dart_vst_graph/lib/src/bindings.dart` | `try/catch` fallback library loading breaks the repo's no-fallback rule | Fixed |
| M15 | `embedded_flutter_view.cpp:708` and others | `fprintf` debugging left in | Fixed |
| M16 | `embedded_flutter_view.cpp:1268` | `setFrame` is ignored, and no `IRunLoop` is used on Linux, so GLib timers depend on the host pumping GLib (`:723`) | Fixed |
| M17 | `flutter_vst3/pubspec.yaml` | Flutter SDK dependency breaks the Makefile's `dart pub get` | Fixed |
| M18 | `aot:131-135` | Only the last automation point of each block is used. Not sample-accurate, which should be documented | Fixed |
| M19 | `native:1-22`, `vst3_shared_memory.h:1-25` | Comments claim "zero-copy" and "lock-free", which the code isn't | Fixed |

## PR claims against the code

| Claim | What the code does | Evidence |
|---|---|---|
| "Zero-copy" | Two `memcpy` calls each way per block | `native:264-265,294-295` |
| "No CPU spinning or polling", microsecond wakeups | `sem_trywait` plus `sleep_for(100us)`, up to 500 times | `native:284-290` |
| "Lock-free" | `std::mutex` on the audio thread, plain non-atomic indices | `native:261,305` |
| "Safety timeout, never freezes" | 50 ms per block when dead, nominally. Windows sleep granularity can stretch it to seconds (reasoned, not measured) | `native:273-279` |
| "Zero allocations verified" | Four `asTypedList` views per block, plus `dynamic` dispatch | `vst3_shared_memory_processor.dart:330-334` |
| "Graceful fallback" | Blank editor on asynchronous mount failure on Windows and Linux | B14 |
| "Multi-instance tested" | Only different plugins could work. Same-plugin instances share one global | B5 |
| `test/vst3_test.dart` all passing | The file doesn't exist. Only `vst3_shared_memory_test.dart` does | Repo tree |
| Logic Pro listed as a host | Logic hosts AU, not VST3 | |
| Real host testing | Tested in flutter_soloud, a Flutter/GTK host. No evidence of a real DAW | PR description |

## Missing tests

Ranked by the damage a regression would do.

1. IPC round trip between real C++ host code and a real compiled Dart worker, on POSIX and Win32
2. Timeout, then recovery with correct output (B1)
3. Dead worker: bounded cost and no per-block stall (B8)
4. Sample rate and block size change reaching the DSP (B2)
5. Blocks over 4096 samples (B4)
6. Two instances of one plugin: DSP isolation and independent disposal (B5)
7. Parameter ring overflow and 2^32 index wrap (B7, H1)
8. C++ and Dart layout parity (H3)
9. Reader validity after dispose, including Windows (B9)
10. `mmap` and `sem_open` failure (H2)
11. Saved state reaching the DSP (B6)
12. One begin/end pair per drag (H10) and no UI echo loop (H11)
13. Multi-editor open and close ownership on Windows and Linux (B13)
14. Non-Echo plugin entrypoint (B12) and mount failure fallback (B14)
15. Module unload with a live engine: needs a runtime check
16. Steinberg validator in CI (H17)
17. Smoke test in a real DAW such as Reaper: manual, not automated
18. Widget tests with a mocked `MethodChannel`
19. Child, shm and semaphore leak checks on shutdown and failure (B3)
20. Echo: impulse timing at a known delay, bypass tail (H21), saturation continuity (H23)

## The test harness hides failures

| ID | Where | Problem | Status |
|---|---|---|---|
| T1 | `Makefile:57,59,61` | `dart test \|\| true` for `flutter_vst3`, reverb and echo, so they can never fail | Fixed |
| T2 | `Makefile:92-93,104-105` | `cp` runs from the wrong directory after `cd`, hidden by `\|\| true`, so libraries aren't copied | Fixed |
| T3 | `build.ps1:150` | `Run-Tests` covers only host and graph, and doesn't check `$LASTEXITCODE` | Fixed |
| T4 | `vsts/echo/test/widget_test.dart` | Imports Flutter, so it fails under `dart test`, hidden by T1 | Fixed |
| T5 | `dart_vst_host/test/host_test.dart:151,174,257,291` | Hardcoded `/workspace/...` paths | Fixed |
| T6 | `dart_vst_host/test/host_test.dart:286-346` | The "load plugin" test catches everything and prints, so it can't fail | Fixed |
| T7 | `dart_vst_host/test/host_test.dart:90` | The "audio generation" test never touches the host | Fixed |
| T8 | `vsts/flutter_reverb/test/reverb_test.dart` | A plain `main` with asserts and no `test()`. `flutter test` reports "No tests ran" and exits non-zero | Fixed |
| T9 | `vsts/echo/test/echo_test.dart` | Assertions are too weak: `any != 0`, "obvious echo" checks only the first dry sample, and the click threshold is 0.95 | Fixed |
| T10 | `flutter_vst3/test/vst3_shared_memory_test.dart:61` | `0x0200` is `O_CREAT` only on macOS. On Linux it's `O_TRUNC`, so the test can write to fd `-1` and segfault. POSIX lookups also fail on Windows | Fixed |
| T11 | Repo | No CI on this branch | Fixed |

## Credit

These parts are good and should stay: the `Float32List` migration, correct header offsets (checked by hand), `ui.dart` keeping the headless worker free of Flutter, the Windows setup and build scripts, Release build defaults, Cocoa class prefixes, the POSIX `MAP_FIXED` remap that keeps UI memory valid, and the choice to run DSP out of process.

## Decision for the maintainer

`CLAUDE.md` says "Only native machine code. No AOT or Dart runtime!" and asks for FP style with no classes. This design ships
a `dart compile exe` binary, which is AOT plus the Dart runtime, and the VST3 SDK requires classes. The fixes follow the
existing design because no other in-process option exists today. Those rules should be reworded to match.

`aot:86-90,169-174` deliberately call `abort()` in the host when something fails. The repo says "FAIL HARD", but this takes
down the user's whole DAW session and unsaved work. The fixes fail through the VST3 API instead: `setActive` returns an
error, `process` returns `kNotInitialized` with silence. The failure is still visible to the host. Revert this if crashing is really what you want.

## How this review was done

The first pass was static, cross-checked with `pi` agents whose claims were verified by hand. Some of their claims were
rejected: POSIX `SIGSEGV` after dispose (the mapping stays valid), and off-main-thread `removed()` (`IPlugView` is
UI-thread only). Items that were only reasoned about, and not reproduced, are marked as such.

## Fix log

### Tests that prove each finding

| Findings | Test | Where |
|---|---|---|
| B1, B7, B8, DSP exception | `B1 recovers after a late block`, `B7 stall is bounded`, `B7 parameters survive a stall`, `B8 dead worker is bounded`, `B8 worker exits when the host dies`, `DSP exception is detected` | `flutter_vst3/test/native/ipc_host_recovery_test.cpp`, `ipc_host_test.cpp` |
| B2, B3, B4, B5, B9, B10 | The cases of the same names, against a real compiled Dart worker, and again against the built Echo | `ipc_host_test.cpp`, `plugin_host_test.cpp` |
| B6 | `B6 saved state reaches the DSP`, `B6 truncated state is rejected` | `plugin_host_test.cpp` |
| B11, B12, B14 | `B12/B14 positive`, `B14 broken bundle fallback`. Opening a Windows editor with parameters is what deadlocked in B11. B12 also has `B12: the Flutter entrypoint reaches the CMake metadata` | `editor_host_test.cpp`, `generate_plugin_test.dart` |
| B13 | `B13 owner closed first`, `B13 secondary closed first`, `B13 same view chooses Flutter again` | `editor_host_test.cpp` |
| H1, H2, H3 | `parameter ring crosses uint32 wrap and writes read index`, `POSIX failure sentinels are checked without dereferencing`, `every native protocol define matches Dart` | `vst3_worker_loop_test.dart`, `vst3_shm_layout_test.dart` |
| H7 | `H7 activation sender and forwarding`, `H7 foreign pid accepted without crash`, `H7 deactivation payload` | `editor_host_test.cpp` wire mode |
| H8 | `reader invalidation and bounded sample counts` | `shared_memory_reader_test.dart` |
| H10, H11 | `one begin/set/end gesture per knob drag and bypass`, `pointer completed and interrupted gestures`, and the edit suppression checks in `view_logic_test.cpp` | `ui_regression_test.dart`, `editor_host_test.cpp` |
| H17 | The validator on Echo and Reverb: 47 of 47 on all three OSes | `run_plugin_e2e.sh`, `run_editor_e2e.sh` |
| H20 | Reverb's fail-hard cases | `reverb_test.dart` |
| H21, H22, H23, H24 | `bypass records incoming audio and advances tail`, `impulse timing`, `H23: saturation has continuous value and slope at the threshold`, `physical parameter formatting` | `dsp_regression_test.dart`, `ui_regression_test.dart` |
| M5, M6 | `waveform fetch is attachment-driven, not timer or parameters`, `single sample waveform is finite` | `ui_regression_test.dart` |
| M16 | The Linux test host provides `IRunLoop` and pumps only that, as a host does, and the editor still starts and draws | `editor_host_platform_x11.cpp` |
| T1, T3, T4, T8, T9, T10, T11 | `dart_vst_host/test/native/harness_test.sh` injects a failure into each of 5 packages and checks `make test` exits with it. The rewritten package tests, and `.github/workflows/ci.yml` | |
| H4, H5, H6 | `exclusive resources, sentinels and permissions`, `full owner names with identical low 16 bits`, `detached worker has no visible or new console window`, `failed exec never runs host atexit handlers` | `ipc_platform_test.cpp` |
| H12, H13 | `H12 DLL directory invariant`, `H13 GDK_BACKEND invariant before and after GTK initialization` | `editor_host_regressions.h`, `environment` mode |
| H14 | `H14 separate module unload and survivor slider`: two copies of the plugin, one unloaded, then a real drag on the survivor | `editor_host_test.cpp`, `modules` mode |
| H15 | `H15 dead/live/expired token exact work counts`, `H15 immediate close` | `editor_liveness_test.cpp`, `immediate` mode |
| H18, H19 | `test_H18_release_never_uses_debug_bundle`, `test_H19_missing_ephemeral_is_fatal`, `test_H19_runpath_is_origin_relative` | `build_rules_flutter_test.py` |
| M1 | `avoid_print` and `empty_catches` as analyzer errors | `flutter_vst3/analysis_options.yaml` |
| M7 | Version floors parsed from both pubspecs | `build_rules_versions_test.py` |
| M14 | `M14 missing graph library throws with attempted library name` | `dart_vst_graph/test/missing_library_test.dart` |
| M17, T2 | `test_M17_clean_dart_deps_resolves_all_packages`, under a `dart` that refuses Flutter packages as a standalone one does. `test_T2_native_copies_fresh_libraries` | `build_rules_make_test.py` |
| T6, T7 | A real SDK plugin is loaded and rendered, and all 512 samples of both outputs are asserted exactly | `dart_vst_host/test/host_audio_regression_test.dart` |
| H9, H16, M2, M3, M4, M8 to M13, M15, M18, M19, T5 | Each is an absence, so a named rule checks it: removed code, tracked binaries by magic bytes, stale claims, absolute paths, and the prefix on every Objective-C class we define | `repo_rules_test.py` |
| AB4 | Extracts the README's test commands, runs each, and requires every package's tests to pass | `docs_commands_test.py` |

### Found while fixing

The first review missed these. Each has a test unless it says otherwise.

| ID | Problem | Fix |
|---|---|---|
| H25 | All plugins shared hardcoded UIDs, so a host saw Echo and Reverb as one plugin | New plugins derive UIDs from the bundle id, and Reverb now has its own. Echo keeps its original UIDs, pinned in `plugin_metadata.json`, so saved Echo projects still find it. **Reverb's UID did change, so projects saved with the old Reverb won't find it**. Tests: `H25: a pinned UID is used exactly`, `H25: a bad pinned UID is rejected`, `H25: Echo keeps its original UIDs, and Reverb has its own`, and `Echo keeps its UID` on the built bundle |
| B15 | Windows release builds never passed the AOT path, so the Flutter editor could never start there | Pass `data\app.so`. Found by the first Windows run of the editor test |
| F1 | A corrupt `App` on macOS crashed the host | Preflight with `dlopen`, and fall back to native sliders |
| F2 | On Windows, the worker didn't exit after a DSP exception | Explicit exit with status 70 |
| F3 | On Windows, the Ninja generator built a broken bundle | `FATAL_ERROR` without a Visual Studio generator. No test, as it's a build-time check |
| F4 | `dart_vst_host` let its `PlugProvider` go out of scope, which terminated the plugin it had loaded | The state owns the provider |
| F5 | Flutter's Linux platform handler calls `exit(0)` on a plug delete event, which would exit the DAW. A close race also gave `BadWindow` | The plug swallows the delete event. The editor test exited early before this, which its completion marker catches |
| F6 | The worker inherited the host's file descriptors | `worker does not inherit descriptors` |
| F8 | A worker crash during playback was silent for the user: audio just stopped. The host now clears the block's magic word, and the Flutter editor shows "DSP stopped" until a new worker starts | `the editor says when the DSP stops, and when it is back`, `a block with a cleared magic word means the worker died`, `B8 dead worker is bounded` |
| F7 | The plugin's RUNPATH held an absolute path from the build machine. Found by the H19 test | Only `$ORIGIN` now |

### Second adversarial review

Four `pi` reviewers attacked the fixed code, read-only, each required to reproduce or point to exact lines. Reports were checked by hand before anything was changed.

| ID | Problem | Before | Test now | Status |
|---|---|---|---|---|
| AI1 | Windows leaked a process handle per dead worker | 20 crashes: 71 to 91 handles | `crash cycles leak nothing` | Fixed |
| AI2 | A partly late block kept audio while flagged silent | `sample 0 is not silent` | `partly late block is wholly silent` | Fixed |
| AI3 | The B1 test passed with recovery removed | Mutant survived | `B1 recovers after a late block` now requires recovery | Fixed |
| AI4 | Echo and Reverb reported no tail, so hosts could cut them off | Tail 0 | `tail is reported`. Reports infinite, because feedback has no fixed length | Fixed |
| AI5 | NaN and out-of-range saved state reached the processor; the controller read a short state as zeros. Found while checking AI | `invalid value must be rejected` | `processor rejects invalid state`, `controller rejects invalid state` | Fixed |
| AG1 | Closing an editor mid-drag left the host's gesture open | Open gesture on the host | `interrupted gesture and fresh begin after reattach`, pointer test | Fixed |
| AG2 | Channel values skipped range and type checks | `getParameter(0)` returned 2.0 | `exact bidirectional contract and atomic rejection` | Fixed |
| AG3 | The editor test passed with parameter sync removed | Mutants survived | `host to UI display sync and reopen`, `pointer completed and interrupted gestures` | Fixed |
| AG4 | `attached` accepted unsupported platform types | Returned success | Asserted on every editor opened | Fixed |
| AG5 | The host could get a perform outside any gesture, after an interrupted drag on Windows. Found by AG3's test on CI | `FAIL drag boundaries`, with performs after the end | Pointer test, and a stray perform in `interrupted gesture`. The controller now drops these | Fixed |
| AG6 | A host value over 1 displayed wrongly in native sliders and was rejected by the Flutter UI. Found by me | `out-of-range value must display as its clamped value` | Part of the display test | Fixed |
| AG7 | On Linux, dragging, closing the editor, releasing, then reopening left the knob dead, because the embedder still thought the button was down. Found by a reordered pointer test | `FAIL drag missing events` | The `releasedWhileClosed` drag in the pointer test. The Linux view now ends the pointer before hiding | Fixed |
| AG8 | On Windows, holding the button through a close and reopen left the host's gesture open. Found by the contract check on CI | `contract: gesture left open`, then a drag with no end | The `releasedAfterReopen` drag. The begin now waits for the first value. Two Windows pointer workarounds tried on the way were removed, as mutants showed no test needed them | Fixed |
| AD1 | Reverb tests passed with its wet output or decay removed | 6 mutants survived | `wet_contract_test.dart`, with landmarks worked out by hand | Fixed |
| AD2 | Echo tests passed with feedback removed | 2 mutants survived | `feedback_contract_test.dart` | Fixed |
| AD3 | Binding tests passed with the wrong id or value sent | 4 mutants survived | `parameter_binding_contract_test.dart` | Fixed |
| AD4 | Quoted or hyphenated names generated C++ that doesn't compile | `SUCCESS`, then g++ errors | `generator_strings_test.py` compiles the output | Fixed |
| AD5 | Docs called maximum feedback "infinite", but it's capped at 0.85 | | Docs corrected, ratio asserted | Fixed |
| AB1 | `build.bat` always ran a Flutter build, which Reverb can't do | Default Windows build failed | CI job `Windows public build and install` | Fixed |
| AB2 | Incremental builds shipped a stale worker, and accepted invalid Dart | Same hash after an edit | `run_incremental_build.sh` | Fixed |
| AB3 | `build.bat test` ran the POSIX IPC script on Windows | | CI runs `build.bat test-native` | Fixed |
| AB4 | The README's test commands used the wrong runner | `dart:ui is not available` | `docs_commands_test.py` | Fixed |

The mutation sweep went from 12 of 14 surviving to 0 of 43. These are hand-picked mutants, so this isn't a project-wide rate.

### What ran where

CI run `41385874459` at `b8857d1`: all 23 jobs green.

| Suite | Linux | macOS | Windows |
|---|---|---|---|
| IPC round trip, 18 cases | Pass | Pass | Pass |
| Built Echo in a host, 11 cases | Pass | Pass | Pass |
| Validator on Echo and Reverb, native and Flutter | 47 of 47 | 47 of 47 | 47 of 47 |
| Editor lifecycle, fallback, H7 wire | Pass | Pass | Pass |
| Interrupted gesture, on the real controller | Pass | Pass | Pass |
| Rendering, host-to-UI display, pointer drag | Pass | **Not run** | Pass |
| Two modules, one unloaded | Pass, with pointer and pixels | Pass, without them | Pass, with pointer and pixels |
| Platform IPC rules (H4, H6 on POSIX, H5 on Windows) | Pass | Pass | Pass |
| Editor mutation job | 3 killed | 1 killed | 3 killed |
| Public `build.bat` commands | n/a | n/a | Pass |
| Incremental build, generator output, repo rules, build rules, README commands, `flutter_vst3`, Echo and Reverb packages | Pass | Not run | Not run |
| Host and graph libraries | Pass | Pass | Not run |

### Evidence that the tests can fail

- `plugin_host_test` on the original PR (`63b646d`): 7 of 7 failed, including B2 with the echo at sample 2832 not 4800, and B4 with sample 4096 not rendered. Leftover `/dev/shm/vst3_shm_*` files proved the B3 leak.
- A leak planted in the IPC run makes `run.sh` exit 1. `red_B13.log` and `red_B14.log` show those cases exit 1 with the fix disabled.
- **Sweep on final code** (`d9344c4`): all 43 mutants killed by a test assertion, with none surviving. 35 are Dart and 8 are editor. After that commit, only Windows pointer code, the macOS test host and the test runner changed, none of which those mutants touch.
- **CI's `Editor mutation proof` job** undoes fixes on each OS and requires the expected failure. It kills `linux_release`, `h13` and `h15` on Linux, `h12`, `h14` and `h15` on Windows, and `h15` on macOS.
- **Each finding added for lack of a test** was seen failing when its fix was undone, in a scratch copy. H5's mutant ran on Windows. Logs are in the agents' reports.
- **Survivors were acted on.** Mutants removing `releasePointer` and `ignoreHeldButton` on Windows survived, so that code was deleted. M17's first mutant survived because this toolchain's `dart` comes with Flutter, so the test now models a standalone one.
- **Not every test failed before its fix.** Tests over code that already worked, including those added for this section, were proven by mutation. AG1's host-level tests were written after its fix: the unit test failed first, and a mutation proves the rest.

### What this does not prove

- **No real DAW has run this.** Everything is the SDK's hosting classes, the validator, and a test host. Try Reaper by hand before release.
- **macOS isn't checked through its real UI.** CI has no screen capture or input permission, so rendering, display sync and pointer drags print `NOT RUN`. Its Flutter editor starts, and the gesture logic passes, but nobody has seen it draw in these tests. macOS also has no asynchronous startup watchdog, only the synchronous checks.
- **Pixel checks cover a limited region.** It catches a value changing and returning, not that a label reads correctly. 0.9 and 1.0 look the same to it on the Flutter knob.
- **Some tests check text, not behaviour.** The rules in `repo_rules_test.py` fail if something removed comes back, which is what those findings needed. H16's rule checks that our class names carry the prefix, not how the Objective-C runtime resolves them. M11's tracked-ephemeral branch wasn't separately mutated, though its absolute-path branch was.
- **H15's protection on macOS is partly by proxy.** The liveness check is tested as a unit, and a real close-while-queued runs without crashing. A use-after-free doesn't crash reliably, so that run alone wouldn't prove it.
- **H5 relies on one Windows session's behaviour.** The test detaches from its console so that a wrong flag would open a window. It failed under mutation on a local Windows machine. CI's runs have only shown it pass.
- **H7's address inside the controller can't be observed from a host.** The test checks the message and its forwarding.
- **H10 on native sliders** is tested through real pointer drags on Linux and Windows, but not on Cocoa.
- **"DSP stopped" isn't tested end to end.** The IPC test proves the host clears the magic word, and the widget test proves the editor reacts to it, on the same memory layout. No test kills a real worker under an open editor.
- **Module unload with a live engine** is only exercised by the test process exiting.
- **Audio-thread timing** was measured on CI and WSL, not under real load. An offline render waits up to 30 seconds for a worker that hangs.

### Assumptions behind the choices

Made without asking, on the owner's instruction to use judgment. Each can be reversed.

| Choice | Assumption | If it's wrong |
|---|---|---|
| Echo keeps its original UIDs, pinned in metadata | Echo is the plugin people have saved projects with | Delete `processorUid` and `controllerUid` from `vsts/echo/plugin_metadata.json` |
| Reverb gets a new UID, not Echo's | The two can't share a UID in one host, and Reverb had no working editor on `main`, so few projects use it | Pin a different pair in Reverb's metadata. They can't both have the old pair |
| A failure reports an error through the VST3 API, not `abort()` | "Fail hard" means visibly, not by taking down the user's DAW and unsaved work | Put `abort()` back in `setActive` |
| A dead worker restarts at the next activation, not by itself | Starting a process from the audio thread isn't acceptable, and a restart thread isn't worth its cost | Add a restart thread in `Vst3IpcHost` |
| "DSP stopped" shows in the Flutter editor only | Most users see that editor. **The native slider fallback, which Reverb always uses, shows no message** | Add it to each native UI |
| The editor checks for a new worker about once a second | A one-second delay in clearing the message doesn't matter | Change `_restartCheckTicks` |
| A saved state with a bad value is rejected whole | Clamping would silently change a user's project | Clamp in `vst3ReadPluginState` |
| No PR to `main` opened | The owner said not to open PRs, and hasn't changed that. **Nothing can merge until one exists** | Open one from this branch |
| Light agentpmo means agent files and Makefile targets | "Light" rules out the rest of the standard: coverage thresholds, Dependabot, CodeQL, a release workflow, Deslop, the shipwright check and repo settings. None was applied, and `make test` doesn't enforce coverage | Run the `agent-pmo` skill for the full conversion |
| `CLAUDE.md` stays canonical, with `AGENTS.md` a pointer | The spec keeps a substantial existing `CLAUDE.md` as canonical. `GEMINI.md` was already a symlink to it | Swap the two |
| CI runs on pushes to `feature/**` as well as on PRs | The owner wanted proof on this branch before any PR exists | Remove the trigger before merging, as the standard is PR-only |

### Decisions

- H16: `Won't fix` for the Flutter framework's own classes, since those lookups are process-wide by Objective-C's design and aren't ours to prefix. Our own classes are prefixed.
- Interrupted gestures end on close, instead of asking the host to cope. Late messages from Dart are ignored.
- A gesture reaches the host at its first value, not at pointer down. A tap on a knob therefore makes no undo step.
- Saved state with a bad value is rejected whole. Clamping would silently change a user's project.

### Branch cleanup

Useful code was consolidated in `a140df6`, then these were deleted. They can be restored from these SHAs.

| Branch | SHA |
|---|---|
| `flutter_ui` | `039802a1163a606acac31abd818b0533813c1dcf` |
| `flutter_ui2` | `040e8db65537f049599eb7322d6ec76c57f6f28d` |
| `rebrand` | `908c90f925ee7b7bcfab527e449d7ae87182c486` |
| `ci/root-gate` | `fcab2e84ecb77f9af13ba7fc34e6ae2825dc4487` |
| `fromSoloud` (local) | `d152d9e` |
