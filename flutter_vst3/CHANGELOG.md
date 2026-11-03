## 0.2.0

**Breaking:** DSP now runs in a separate compiled worker process, so plugins must move to the new entry point.

- Removed obsolete same-process VST3Bridge registration and FFI callbacks; use the shared-memory worker.
- Removed `VST3Processor`, `VST3Bridge`, `VST3ParameterHandler` and `VST3ParameterInfo`. Implement `Vst3WorkerProcessor` and pass it to `runVst3SharedMemoryProcessor` instead. See `create_plugin_guide.md`.
- Each plugin instance now runs its DSP in its own `dart compile exe` worker, connected to the host over shared memory. A worker that dies or runs late gives silence instead of taking down the DAW, and restarts at the next activation.
- Added the embedded Flutter editor for macOS, Windows and Linux. Linux needs X11: `GDK_BACKEND=x11`.
- Added `package:flutter_vst3/ui.dart` with `VST3ParameterBinding`, `RotaryKnob` and `Vst3AudioBufferReader`.
- `flutterEntrypoint` in `plugin_metadata.json` names the Dart function the editor starts on macOS and Windows. Linux always runs `main`, so a plugin's `main` must call that function.

## 0.1.2

* Corrections

## 0.1.1

* Fix image URL

## 0.1.0

* Initial release of flutter_vst3 framework
* Complete framework for building VST® 3 plugins with Flutter UI and Dart audio processing
* Auto-generation of all C++ VST® 3 boilerplate code from Dart parameter definitions
* Native performance with compilation to machine code (no Dart runtime)
* Cross-platform support for macOS, Windows, and Linux
* 3-way parameter binding system (DAW ↔ Flutter UI ↔ Audio Parameters)
* VST3Processor base class for implementing audio processing in pure Dart
* VST3Bridge for Flutter UI ↔ VST® host communication
* Complete step-by-step plugin creation guide
* Compatible with Steinberg VST® 3 SDK