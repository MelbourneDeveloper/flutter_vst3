# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Dart Rules
- NO DUPLICATION. Move files, code elements instead of copying them. Search for elements before adding them.
- NO PLACEHOLDERS!!! If you HAVE TO leave a section blank, fail LOUDLY by throwing an exception.
- FP style. No interfaces, classes, or mutable state. Pure functions with no side effects.
- Tests must FAIL HARD. Don't add allowances and print warnings. Just FAIL!
- Keep functions under 20 lines long.
- NEVER use the late keyword
- Do not use Git commands unless explicitly requested
- Keep files under 400 LOC, even tests
- Document all public functions with Dart /// doc, especially the important ones
- Don't use if statements. Use pattern matching or ternaries instead.

## Project Overview

This a VST3 toolkit for Dart and Flutter. Use this toolkit to implement VSTs and VST hosts. This toolkit enables anyone to create VST3s with pure Dart and Flutter.

As part of the toolkit, there is a VST3 host and audio graph system written in Dart with native C++ components. The project enables loading VST3 plugins into a customizable audio graph that can be controlled from Dart and Flutter applications.

Download Steinberg SDK here:
https://www.steinberg.net/vst3sdk
curl -L -o vst3sdk.zip https://www.steinberg.net/vst3sdk

### Core Components

1. **dart_vst_host** - High-level Dart bindings for VST3 plugin hosting with RAII resource management
2. **dart_vst_graph** - Audio graph system allowing connection of VST plugins, mixers, splitters, and gain nodes
3. **flutter_ui** - Desktop Flutter application providing a GUI for the VST host
4. **native/** - C++ implementation of VST3 host and audio graph using Steinberg VST3 SDK
5. **plugin/** - VST3 plugin that wraps the Dart graph system for use in DAWs

### Architecture

The system uses FFI to bridge Dart and C++. The native library (`libdart_vst_host.dylib/so/dll`) contains both VST host functionality and the audio graph implementation. Dart packages provide high-level APIs that manage native resource lifetimes using RAII patterns.

The audio graph supports:
- VST3 plugin nodes
- Mixer nodes (multiple stereo inputs → single stereo output)  
- Splitter nodes (single stereo input → multiple stereo outputs)
- Gain nodes with dB control
- Arbitrary connections between compatible nodes

## Build Requirements

### Prerequisites
- **VST3_SDK_DIR environment variable** must point to Steinberg VST3 SDK root
- CMake 3.20+
- C++17 compiler
- Dart SDK 3.0+
- Flutter (for UI component)

### Build Commands

**Native Library (Required for all Dart components):**
```bash
cd native/
mkdir build && cd build
cmake ..
make
# Copies libdart_vst_host.dylib to project root for Dart tests
cp libdart_vst_host.dylib ../../
```

**VST3 Plugin:**
```bash
cd plugin/
mkdir build && cd build  
cmake ..
make
# Output: dvh_plugin.vst3 bundle
```

**Dart Packages:**
```bash
# In dart_vst_host/ or dart_vst_graph/
dart pub get
dart test
```

**Flutter UI:**
```bash
cd flutter_ui/
flutter pub get
flutter run
```

## Testing

**Run all Dart tests:**
```bash
# From dart_vst_host/
dart test

# From dart_vst_graph/
dart test
```

**Run single test:**
```bash
dart test test/specific_test.dart
```

**Important:** Tests require the native library to be built and present in the working directory. The test framework will fail with a clear error message if `libdart_vst_host.dylib` is missing.

## Key Files

- `native/include/dart_vst_host.h` - C API for VST hosting
- `native/include/dvh_graph.h` - C API for audio graph
- `dart_vst_host/lib/src/host.dart` - High-level VST host wrapper
- `dart_vst_graph/lib/src/bindings.dart` - FFI bindings and VstGraph class
- `flutter_ui/lib/main.dart` - Flutter application entry point

## Development Workflow

1. Build native library first (required dependency)
2. Set VST3_SDK_DIR environment variable
3. Run Dart tests to verify FFI bindings
4. Use Flutter UI for interactive testing
5. Tests will fail loudly if native dependencies are missing

## Platform-Specific Notes

- **macOS:** Outputs `.dylib` and `.vst3` bundle
- **Linux:** Outputs `.so` library  
- **Windows:** Outputs `.dll` library
- All platforms require VST3 SDK and appropriate build tools