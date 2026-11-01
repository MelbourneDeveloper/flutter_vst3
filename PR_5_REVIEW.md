# Review: PR #5, shared-memory DSP and embedded Flutter GUI

| | |
|---|---|
| PR | [#5](https://github.com/MelbourneDeveloper/flutter_vst3/pull/5), `alnitak:fromSoloud` at `d152d9e` |
| Merged to | `feature/soloud-shared-memory-gui` as `63b646d` (not `main`) |
| Diff reviewed | `main` (`39d5e42`) to `63b646d`: 26 commits, 119 files |
| Line numbers | All `file:line` references are at `63b646d` |
| Verdict | **Do not merge to `main` until every blocker is closed** |

Status values: `Open`, `Fixed` (the named test proves it), `Fixed, untested on this OS`, `Won't fix` (reason given). The
[fix log](#fix-log) records how each item was closed.

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
| B1 | `native:269-299` | One block takes over 50 ms, such as a Dart GC pause or a scheduler stall | The late `sem_done` stays posted, so the next block takes it at once and copies the previous output. The host then overwrites input while the worker is reading it. It never recovers | The host owns shared memory only between "done" and "ready". After a timeout it leaves shared memory alone, outputs silence, and resyncs when the late "done" arrives | Round trip with a real worker: stall one block, then assert later blocks return their own output | Open |
| B2 | `aot:83,106-109` | Host runs at anything but 44.1 kHz, or changes rate or block size | `setupProcessing` stores the rate, but `initialize` returns early when already set up (`native:119`), and block size is hardcoded to `512`. A second activation at a new rate leaves the DSP on the old one, so delay times are wrong | Pass `setup.sampleRate` and `setup.maxSamplesPerBlock`, and reconfigure the live worker on activation | Activate at 44.1k, reactivate at 96k, assert the worker sees 96k | Open |
| B3 | `native:404-411`, `aot:82-84` | Worker missing, or handshake fails | `native_initialize` swallows the exception, the caller sets `nativeProcessorInitialized = true`, and the plugin is silent with no error. The `catch`/`abort` in `aot` is unreachable. Shared memory, semaphores and the child leak | Roll back all resources on failure and return failure from `setActive` | Missing exe and exe that exits at once: both fail fast, leaving no child, shm or semaphores | Open |
| B4 | `native:262,293-299` | Block larger than 4096 samples, such as offline render | Only the first 4096 samples are processed. Samples past that in `output` are never written, so the host plays stale memory | Process in chunks of up to 4096 samples | 10000-sample block matches the same audio in small blocks | Open |
| B5 | `native:401,406` | Two instances of one plugin in a session | `g_processor` is per module. Both instances share one DSP and one parameter set, and audio passes through a single delay line. Disposing either kills both | One host object per plugin instance | Two instances keep separate DSP state, and disposing one leaves the other working | Open |
| B6 | `aot:181-197` | Save and reload a project | `getState`/`setState` use C++ member doubles that `process()` never updates, and nothing forwards them to Dart. Saved projects restore defaults | Track values in `process()`, and replay state to the worker before audio starts | Automate, get state, load into a new instance, assert the DSP received the values | Open |
| B7 | `native:261,269-291`, `native:303-315` | Every block | Audio thread holds a mutex, sleeps in a poll loop, and can block for 50 ms against a block budget of a few ms. A full parameter ring drops automation | No mutex or fixed 50 ms wait. Base the budget on block length with a real timed wait, and keep the latest value when the ring is full | Timing test: stalled worker costs at most one budget. Overflow test: the last value arrives | Open |
| B8 | `native:223-235` | Worker dies mid-session | Every later block stalls 50 ms and outputs silence, and the host's audio thread runs far behind. On Linux, `PR_SET_PDEATHSIG` also fires when the *spawning thread* exits, so the worker can die while the DAW lives. Other platforms orphan the worker if the host dies | Detect a dead child and skip the wait. Have the worker watch the host process directly | Kill the worker: later blocks return silence immediately. Kill the host: the worker exits | Open |
| B9 | `native:328` | Windows: two instances, editor open on A, delete B | `UnmapViewOfFile` frees memory the UI reader still reads, so the host crashes. POSIX is safe through the `MAP_FIXED` remap | Keep the Windows view mapped with `magic = 0`, and reuse it | Reader stays valid and reads `isValid == false` after dispose on both OSes | Open |
| B10 | `native:317`, `aot:94-96` | Stop transport, or `setActive(false)` | `reset()` is an empty body, so old tails play on restart | Add a reset command that reaches the DSP | Reset clears an echo tail in a round trip | Open |

### Embedded GUI

Paths are under `flutter_vst3/native/src/`.

| ID | Where | Trigger | Failure | Required fix | Proof required | Status |
|---|---|---|---|---|---|---|
| B11 | `embedded_flutter_view.cpp:146,227,262` | Windows: open an editor on a plugin with parameters | `mount` holds a non-recursive `std::mutex`, calls `updateParam`, which locks it again. That's undefined behaviour and in practice a deadlock or abort | Split into locked and unlocked functions | Windows compile plus a test on the extracted logic | Open |
| B12 | `embedded_flutter_view.cpp:156,168` | Any plugin other than Echo on Windows and Linux | Entrypoint is hardcoded to `"echoMain"`. Reverb's editor can't start | Take the entrypoint from `plugin_metadata.json` and pass it as a compile definition | Generator test: the entrypoint reaches CMake metadata | Open |
| B13 | `embedded_flutter_view.cpp:247-268,891-913` | Two editors open, close one | `sActiveController` is cleared unconditionally and `updateParam` has no instance check. Editor B drives A's parameters and closing A blanks B | Check ownership on shutdown and update | Test of the extracted ownership logic | Open |
| B14 | `embedded_flutter_view.cpp:1216,1228,1231` | Flutter engine fails to start | `attached` ignores the failure and returns `kResultTrue`, leaving a blank editor. The PR claims a graceful fallback | Return failure, or mount the native sliders that already exist | Force init failure: native UI appears or `attached` fails | Open |

## High

| ID | Where | Problem | Fix | Status |
|---|---|---|---|---|
| H1 | `flutter_vst3/lib/src/vst3_shared_memory_processor.dart:339-349` | `readIdx++` is an unbounded Dart int but `writeIdx` is `Uint32`. At the 2^32 wrap, `readIdx != writeIdx` never ends and the worker hangs | Mask to 32 bits, with a wrap test | Open |
| H2 | same file `:165-172` | `mmap` is compared with `nullptr`, not `MAP_FAILED`. `sem_open` results aren't checked, so a failure segfaults later | Check both and throw | Open |
| H3 | same file, plus `vst3_shared_memory.h` | Layout constants are hand-copied in Dart, `version` is never validated, and C++ has no `static_assert` | `static_assert` in C++, a test parsing the header against Dart constants, and a version check | Open |
| H4 | `native:123,195,217-218` | Names use only 16 bits of `this`. On Windows, a collision opens the existing mapping and `memset`s another instance's audio. Mode `0666` lets any local user read or inject audio | Full pointer in the name, exclusive creation, mode `0600` | Open |
| H5 | `native:166` | `CreateProcessA` flags are `0`, so a console window pops up with each instance on Windows | `CREATE_NO_WINDOW` | Open |
| H6 | `native:234` | `exit(1)` after `fork` runs host static destructors in the child | `_exit` | Open |
| H7 | `flutter_vst3/native/src/vst3_shared_memory.cpp:7-15` | Process-global "active shm": last writer wins, so editor A shows instance B's waveform. Closing either instance nulls it for both | Route the address from processor to controller over `IConnectionPoint` | Open |
| H8 | `flutter_vst3/lib/src/shared_memory_reader.dart:46-54,124-139` | `try/catch` around a raw pointer deref can't catch a segfault. `numSamples` isn't clamped | Rely on B9 for validity, remove the catch, clamp | Open |
| H9 | `flutter_vst3/lib/src/flutter_vst3_bridge.dart:44-56` | `registerProcessor` now always throws, but `vsts/echo/lib/src/echo_bridge.dart:14` calls it and `flutter_vst3/README.md:60` documents it. The export of `flutter_vst3_callbacks.dart` was removed without a changelog entry | Remove the stale API, caller and docs, or restore it | Open |
| H10 | `embedded_flutter_view.cpp:307-310,764-767`, `:510-513,1059-1062`, `embedded_flutter_view.mm:240-243`, `native_cocoa_view.mm:22-25` | Each drag tick sends begin, perform and end, so a single gesture becomes hundreds of automation undo steps | One begin and end per gesture, with channel methods for Dart | Open |
| H11 | `plugin_controller.cpp.template:44-50` | `setParamNormalized` echoes the UI's own edits back, so sliders jitter during a drag | Skip the echo while the parameter is being edited | Open |
| H12 | `embedded_flutter_view.cpp:128` | `SetDllDirectoryW` changes host-wide DLL search and is never restored | Restore it, or use `LoadLibraryExW` with full paths | Open |
| H13 | `embedded_flutter_view.cpp:710-712,949-950` | `setenv("GDK_BACKEND")` and `gdk_set_allowed_backends` change the whole host process | Skip when GTK is already initialized, and document the X11 requirement | Open |
| H14 | `embedded_flutter_view.cpp:397-423` | A fixed window class name registers under the host `hInstance` with this DLL's `wndProc`. A second plugin gets the first plugin's window procedure, which is a crash once that module unloads | Use a per-module class name and the module's own `HINSTANCE` | Open |
| H15 | `embedded_flutter_view.mm:85-89,230-233` | `dispatch_async` captures raw `this`, and `weakCtrl` is a raw pointer, so it's use-after-free if the view closes first | Liveness token checked in the block | Open |
| H16 | `embedded_flutter_view.mm:49-51`, `native_cocoa_view.h:10-14` | Flutter framework class lookups are process-wide. Objective-C classes in embedded view code can collide between plugins | Per-plugin class prefix everywhere | Open |
| H17 | `flutter_vst3/native/cmake/VST3Bridge.cmake:44-45` | The Steinberg validator is turned off | Turn it on and run it in CI | Open |
| H18 | `VST3Bridge.cmake:385-387,420-422,450-452` | Release builds silently fall back to the Debug Flutter bundle | `FATAL_ERROR` | Open |
| H19 | `VST3Bridge.cmake:314-316` | Windows and Linux silently drop the embedded GUI when `ephemeral` is absent at configure time. No `$ORIGIN` RPATH was found for `libflutter_linux_gtk.so` | Fail or say so with `message(STATUS)`, and set the RPATH | Open |
| H20 | `vsts/flutter_reverb/lib/src/reverb_processor.dart:139-142` | `processStereo` returns silently when uninitialized or on a length mismatch, leaving output unwritten. Breaks the repo's fail-hard rule | Throw, as Echo does | Open |
| H21 | `vsts/echo/lib/src/echo_processor.dart:93-96` | Bypass doesn't feed the delay line or advance the write index, so unbypassing replays a frozen tail | Keep the delay line running during bypass | Open |
| H22 | `vsts/echo/lib/src/echo_processor.dart:7,98` | Delay is 10-500 ms but docs and metadata say 0-1000 ms. The fixed 132300-sample buffer also clamps delay at high rates | Match the docs and size the buffer from the sample rate | Open |
| H23 | `vsts/echo/lib/src/echo_processor.dart:125-128` | `_softSaturate` jumps from 1.0 to 0.5 at the threshold, which adds a click in the feedback path | Continuous curve, with a test | Open |
| H24 | `vsts/echo/lib/ui/echo_ui.dart:56` | Shows `value*100` with the units, so "50.0ms" appears for a real delay of about 255 ms | Format from each parameter's real range | Open |

## Medium and low

| ID | Where | Problem | Status |
|---|---|---|---|
| M1 | `flutter_vst3/lib/src/parameter_binding.dart:48-55,81,178` | `print` debugging and `catch (_) {}` hide failures | Open |
| M2 | `parameter_binding.dart:189-224` | Dead `VST3AudioProcessor` class describing the rejected same-isolate design | Open |
| M3 | `vsts/echo/lib/src/echo_processor.dart:114-122` | `waveformBuffer` is unreachable because the UI runs in another process, and it costs CPU each block | Open |
| M4 | `vsts/echo/lib/ui/echo_ui.dart:2` | Comment claims the UI shares a process with the DSP | Open |
| M5 | `vsts/echo/lib/ui/echo_ui.dart:198,206,219` | Forces a channel call on every parameter change, and every 33 ms when there is no reader | Open |
| M6 | `vsts/echo/lib/ui/echo_ui.dart:307` | Divides by zero with a single sample | Open |
| M7 | `vsts/echo/lib/ui/echo_ui.dart:91,95`, `pubspec.yaml` | Uses `withValues` and `activeThumbColor` while pubspecs allow Flutter `>=3.0.0` | Open |
| M8 | `flutter_vst3/native/src/flutter_embedder.cpp`, `flutter_embedder_stubs.cpp`, `include/flutter_embedder.h` | Unbuilt code. The first defines `class FlutterEmbedder` twice and can't compile, and the stubs return fake handles such as `0x1234` | Open |
| M9 | `flutter_vst3/native/src/plugin_view.cpp:86` | Unbuilt, and runs `system()` with a hardcoded `/Users/christianfindlay/...` path | Open |
| M10 | `vsts/echo/echo_processor` | 5.6 MB committed Mach-O binary | Open |
| M11 | `vsts/echo/macos/Flutter/ephemeral/*`, `.vscode/settings.json` | Machine-specific paths committed | Open |
| M12 | `vsts/echo/README.md` | Flutter template boilerplate | Open |
| M13 | `FLUTTER_UI_SPEC.md` | Calls same-isolate UI "non-negotiable", which the implementation contradicts | Open |
| M14 | `dart_vst_graph/lib/src/bindings.dart` | `try/catch` fallback library loading breaks the repo's no-fallback rule | Open |
| M15 | `embedded_flutter_view.cpp:708` and others | `fprintf` debugging left in | Open |
| M16 | `embedded_flutter_view.cpp:1268` | `setFrame` is ignored, and no `IRunLoop` is used on Linux, so GLib timers depend on the host pumping GLib (`:723`) | Open |
| M17 | `flutter_vst3/pubspec.yaml` | Flutter SDK dependency breaks the Makefile's `dart pub get` | Open |
| M18 | `aot:131-135` | Only the last automation point of each block is used. Not sample-accurate, which should be documented | Open |
| M19 | `native:1-22`, `vst3_shared_memory.h:1-25` | Comments claim "zero-copy" and "lock-free", which the code isn't | Open |

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
| T1 | `Makefile:57,59,61` | `dart test \|\| true` for `flutter_vst3`, reverb and echo, so they can never fail | Open |
| T2 | `Makefile:92-93,104-105` | `cp` runs from the wrong directory after `cd`, hidden by `\|\| true`, so libraries aren't copied | Open |
| T3 | `build.ps1:150` | `Run-Tests` covers only host and graph, and doesn't check `$LASTEXITCODE` | Open |
| T4 | `vsts/echo/test/widget_test.dart` | Imports Flutter, so it fails under `dart test`, hidden by T1 | Open |
| T5 | `dart_vst_host/test/host_test.dart:151,174,257,291` | Hardcoded `/workspace/...` paths | Open |
| T6 | `dart_vst_host/test/host_test.dart:286-346` | The "load plugin" test catches everything and prints, so it can't fail | Open |
| T7 | `dart_vst_host/test/host_test.dart:90` | The "audio generation" test never touches the host | Open |
| T8 | `vsts/flutter_reverb/test/reverb_test.dart` | A plain `main` with asserts and no `test()`. `flutter test` reports "No tests ran" and exits non-zero | Open |
| T9 | `vsts/echo/test/echo_test.dart` | Assertions are too weak: `any != 0`, "obvious echo" checks only the first dry sample, and the click threshold is 0.95 | Open |
| T10 | `flutter_vst3/test/vst3_shared_memory_test.dart:61` | `0x0200` is `O_CREAT` only on macOS. On Linux it's `O_TRUNC`, so the test can write to fd `-1` and segfault. POSIX lookups also fail on Windows | Open |
| T11 | Repo | No CI on this branch | Open |

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

Filled in as each item closes.
