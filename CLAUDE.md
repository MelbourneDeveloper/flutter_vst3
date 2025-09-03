# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Code Rules
- NO PLACEHOLDERS. NO FALLBACKS. FAIL HARD!!! If the code is not implemented, THROW AN ERROR!!! Fail LOUDLY by throwing an exception.
- NO DUPLICATION. Move files, code elements instead of copying them. Search for elements before adding them.
- FP style. No interfaces, classes, or mutable state. Pure functions with no side effects.
- Tests must FAIL HARD. Don't add allowances and print warnings. Just FAIL!
- Keep functions under 20 lines long.
- Do not use Git commands unless explicitly requested
- Keep files under 400 LOC, even tests

## Dart Rules
- NEVER use the late keyword
- Document all public functions with Dart /// doc, especially the important ones
- Don't use if statements. Use pattern matching or ternaries instead.
- Only native machine code. No AOT or Dart runtime!


## Project Overview

This a Steinberg VST® 3 toolkit for Dart and Flutter. Use this toolkit to implement VST® plugins and VST® hosts. This toolkit enables anyone to create VST® 3 plugins with pure Dart and Flutter.

*VST® is a trademark of Steinberg Media Technologies GmbH.*

The main project is flutter_vst3. Use this to create your own VST® 3 plugins with Flutter and Dart. There is also VST3 host and audio graph system written in Dart with native C++ components. The project enables loading VST3 plugins into a customizable audio graph that can be controlled from Dart and Flutter applications.

Download Steinberg SDK here:
https://www.steinberg.net/vst3sdk
curl -L -o vst3sdk.zip https://www.steinberg.net/vst3sdk

### Core Components

1. **dart_vst_host** - High-level Dart bindings for VST® 3 plugin hosting with RAII resource management
2. **dart_vst_graph** - Audio graph system allowing connection of VST® plugins, mixers, splitters, and gain nodes
3. **flutter_vst3** - Complete framework for building VST® 3 plugins with Flutter UI and Dart audio processing (auto-generates ALL C++ from Dart parameter definitions)
4. **flutter_ui** - Desktop Flutter application providing a GUI for the VST host
5. **native/** - C++ implementation of VST3 host and audio graph using Steinberg VST3 SDK
6. **vsts/** - Individual VST plugin packages, each builds its own .vst3 plugin (flutter_reverb, echo)

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
- **VST3_SDK_DIR environment variable** must point to Steinberg VST3 SDK root (or use bundled `vst3sdk/` directory)
- CMake 3.20+
- C++17 compiler
- Dart SDK 3.0+
- Flutter (for UI component)

### Build Commands

**Setup (First time):**
```bash
./setup.sh  # Downloads Steinberg VST® 3 SDK and builds native library automatically
```

**Primary build targets using Makefile:**
```bash
# Build Flutter Dart Reverb VST3 plugin (default target)
make

# Build specific plugins
make reverb-vst     # Build Flutter Reverb VST3
make echo-vst       # Build Echo VST3

# Install to system VST folder
make install

# Build native library (required for all Dart components)
make native

# Clean and rebuild
make clean reverb-vst
```

**Manual Native Library Build:**
```bash
cd native/
mkdir build && cd build
cmake ..
make
# Copies libdart_vst_host.dylib to project root for Dart tests
cp libdart_vst_host.dylib ../../
```

**VST3 Plugins (auto-generated from Dart parameter definitions):**
```bash
# Build flutter_reverb plugin
cd vsts/flutter_reverb/
mkdir build && cd build  
cmake ..
make
# Output: flutter_reverb.vst3 bundle

# Build echo plugin
cd vsts/echo/
mkdir build && cd build
cmake ..
make
# Output: echo.vst3 bundle
```

**Dart Packages:**
```bash
# Install dependencies for all packages
make dart-deps

# Or manually:
cd dart_vst_host/ && dart pub get
cd dart_vst_graph/ && dart pub get
cd dart_vst3_bridge/ && dart pub get
```

**Flutter UI:**
```bash
make flutter-deps
cd flutter_ui/
flutter run
```

## Testing

**Run all tests:**
```bash
make test
```

**Run individual package tests:**
```bash
make test-host     # dart_vst_host tests
make test-graph    # dart_vst_graph tests

# Manual test runs:
cd dart_vst_host/ && dart test
cd dart_vst_graph/ && dart test
cd vsts/flutter_reverb/ && dart test
cd vsts/echo/ && dart test
```

**Important:** Tests require the native library to be built and present in the working directory. The test framework will fail with a clear error message if `libdart_vst_host.dylib` is missing.

## VST® 3 Plugin Development (Zero C++ Required)

The flutter_vst3 framework now auto-generates ALL C++ boilerplate from Dart parameter definitions:

1. **Define parameters in Dart** with doc comments:
```dart
class ReverbParameters {
  /// Controls the size of the reverb space (0% = small room, 100% = large hall)
  double roomSize = 0.5;
  
  /// Controls high frequency absorption (0% = bright, 100% = dark) 
  double damping = 0.5;
}
```

2. **CMake auto-generates C++ files**:
```cmake
add_dart_vst3_plugin(flutter_reverb reverb_parameters.dart
    BUNDLE_IDENTIFIER "com.yourcompany.vst3.flutterreverb"
    COMPANY_NAME "Your Company"
    PLUGIN_NAME "Flutter Reverb"
)
```

3. **Generated files** (completely hidden):
   - `generated/flutter_reverb_controller.cpp`
   - `generated/flutter_reverb_processor.cpp` 
   - `generated/flutter_reverb_factory.cpp`
   - `include/flutter_reverb_ids.h`

## Key Files

- `native/include/dart_vst_host.h` - C API for VST hosting
- `native/include/dvh_graph.h` - C API for audio graph
- `dart_vst_host/lib/src/host.dart` - High-level VST host wrapper
- `dart_vst_graph/lib/src/bindings.dart` - FFI bindings and VstGraph class
- `dart_vst3_bridge/native/cmake/VST3Bridge.cmake` - Shared CMake functions for plugin builds
- `vsts/*/CMakeLists.txt` - Individual plugin build configurations
- `flutter_ui/lib/main.dart` - Flutter application entry point
- `Makefile` - Primary build system with all targets
- `setup.sh` - Environment setup script

## Development Workflow

1. Run `./setup.sh` for first-time setup (downloads SDK, builds native library)
2. Use `make` to build Flutter Dart Reverb VST3 plugin  
3. Use `make test` to run all tests and verify FFI bindings
4. Use Flutter UI (`make run-flutter`) for interactive testing
5. Build individual VST plugins in their respective `vsts/` directories
6. Each plugin package is self-contained and builds its own .vst3 bundle
7. Tests will fail loudly if native dependencies are missing

## Platform-Specific Notes

- **macOS:** Outputs `.dylib` and `.vst3` bundle
- **Linux:** Outputs `.so` library  
- **Windows:** Outputs `.dll` library
- All platforms require VST3 SDK and appropriate build tools
- Use `make install` to install VST3 plugins to system folders automatically

## Plugin Validation

```bash
# Validate built plugins
./validate_echo.sh  # Runs VST3 validator on echo plugin
```