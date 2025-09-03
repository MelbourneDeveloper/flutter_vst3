# Creating a New flutter_vst3 Plugin - Step by Step Guide

<img src="VST_Compatible_Logo_Steinberg.png" alt="VST Compatible" width="100">

This guide shows you how to create a new VST® 3 plugin using flutter_vst3 framework with pure Dart and Flutter - **no C++ required**.

*VST® is a trademark of Steinberg Media Technologies GmbH, registered in Europe and other countries.*

## Prerequisites

- Dart SDK 3.0+
- CMake 3.20+
- VST3 SDK (run `./setup.sh` if not already done)

## Step 1: Create Plugin Directory

```bash
mkdir vsts/my_plugin
cd vsts/my_plugin
```

## Step 2: Create pubspec.yaml

```yaml
name: my_plugin
description: My awesome VST3 plugin
version: 1.0.0
publish_to: 'none'

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter_vst3:
    path: ../../flutter_vst3

dev_dependencies:
  test: ^1.24.0
```

## Step 3: Create Directory Structure

```bash
mkdir -p lib
mkdir -p test
```

**Important**: The parameters file goes in `lib/` root, not in a `src/` subdirectory.

## Step 4: Define Plugin Parameters

Create `lib/my_plugin_parameters.dart` (in lib root, not src/):

```dart
/// Parameters for my VST3 plugin
class MyPluginParameters {
  static const int kGainParam = 0;
  static const int kFreqParam = 1;

  /// Controls the output gain (0% = silence, 100% = full)
  double gain = 0.5;
  
  /// Controls the filter frequency (0% = 20Hz, 100% = 20kHz)
  double frequency = 0.5;

  /// Get parameter value by ID
  double getParameter(int paramId) {
    return switch (paramId) {
      kGainParam => gain,
      kFreqParam => frequency,
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Set parameter value by ID
  void setParameter(int paramId, double value) {
    final clampedValue = value.clamp(0.0, 1.0);
    switch (paramId) {
      case kGainParam:
        gain = clampedValue;
        break;
      case kFreqParam:
        frequency = clampedValue;
        break;
      default:
        throw ArgumentError('Unknown parameter ID: $paramId');
    }
  }

  /// Get parameter name by ID
  String getParameterName(int paramId) {
    return switch (paramId) {
      kGainParam => 'Gain',
      kFreqParam => 'Frequency',
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Get parameter units by ID
  String getParameterUnits(int paramId) {
    return switch (paramId) {
      kGainParam => '%',
      kFreqParam => 'Hz',
      _ => throw ArgumentError('Unknown parameter ID: $paramId'),
    };
  }

  /// Get number of parameters
  static const int numParameters = 2;
}
```

## Step 5: Create Plugin Metadata

Create `plugin_metadata.json`:

```json
{
  "pluginName": "My Plugin",
  "vendor": "Your Company",
  "version": "1.0.0",
  "category": "kFx",
  "bundleIdentifier": "com.yourcompany.vst3.myplugin",
  "companyWeb": "https://yourwebsite.com",
  "companyEmail": "you@yourcompany.com"
}
```

## Step 6: Create CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.20)
project(my_plugin 
    VERSION 1.0.0
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  add_compile_definitions(_DEBUG)
else()
  add_compile_definitions(NDEBUG RELEASE)
endif()

# Include the flutter_vst3 bridge helper
include(../../flutter_vst3/native/cmake/VST3Bridge.cmake)

# Create the VST® 3 plugin using auto-generated code from Dart definitions
add_dart_vst3_plugin(my_plugin my_plugin_parameters.dart)
```

## Step 7: Install Dependencies

```bash
dart pub get
```

## Step 8: Create Basic Test

Create `test/my_plugin_test.dart`:

```dart
import 'package:test/test.dart';
import '../lib/my_plugin_parameters.dart';

void main() {
  group('MyPluginParameters', () {
    late MyPluginParameters params;

    setUp(() {
      params = MyPluginParameters();
    });

    test('should initialize with default values', () {
      expect(params.gain, equals(0.5));
      expect(params.frequency, equals(0.5));
    });

    test('should set and get parameters correctly', () {
      params.setParameter(MyPluginParameters.kGainParam, 0.8);
      expect(params.getParameter(MyPluginParameters.kGainParam), equals(0.8));
    });

    test('should clamp parameter values', () {
      params.setParameter(MyPluginParameters.kGainParam, 1.5);
      expect(params.gain, equals(1.0));
      
      params.setParameter(MyPluginParameters.kGainParam, -0.5);
      expect(params.gain, equals(0.0));
    });

    test('should return correct parameter names', () {
      expect(params.getParameterName(MyPluginParameters.kGainParam), equals('Gain'));
      expect(params.getParameterName(MyPluginParameters.kFreqParam), equals('Frequency'));
    });
  });
}
```

## Step 9: Build the Plugin

```bash
mkdir build && cd build
cmake ..
make
```

The `.vst3` plugin bundle will be created in the build directory.

## Step 10: Test Your Plugin

```bash
# Run Dart tests
dart test

# Validate the VST3 plugin (if you have VST3 validator)
# validator my_plugin.vst3
```

## What Happens Behind the Scenes

1. **Auto-Generation**: The CMake system reads your `my_plugin_parameters.dart` file and generates all necessary C++ boilerplate
2. **Generated Files**: Creates controller, processor, and factory C++ files in `build/generated/`
3. **VST3 Bundle**: Packages everything into a proper `.vst3` bundle with metadata
4. **Zero C++**: You never touch C++ - everything is generated from your Dart definitions

## Key Points

- ✅ **Parameter comments become VST3 parameter descriptions**
- ✅ **All C++ is auto-generated from Dart**  
- ✅ **Standard VST3 plugin structure is created automatically**
- ✅ **Follow existing naming patterns**: `*_parameters.dart`
- ✅ **Use descriptive parameter comments with ranges and units**

## Installation

```bash
# Install to system VST3 folder
make install
```

Your plugin is now ready to use in any VST® 3 host!