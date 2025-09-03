# flutter_vst3

Flutter/Dart framework for building VST® 3 plugins with Flutter UI and pure Dart audio processing.

*VST® is a trademark of Steinberg Media Technologies GmbH, registered in Europe and other countries.*

## Overview

`flutter_vst3` is a complete framework that enables you to build professional VST® 3 audio plugins using Flutter for the UI and Dart for real-time audio processing. The framework auto-generates all C++ VST® 3 boilerplate code - you write only Dart and Flutter.

**For complete architecture documentation and examples, see the [main project README](https://github.com/your-org/flutter_vst3_toolkit).**

## Features

- ✅ **Flutter UI** - Build beautiful, reactive plugin interfaces
- ✅ **Pure Dart DSP** - Write audio processing in familiar Dart syntax
- ✅ **Auto-Generated C++** - Never write VST® 3 boilerplate
- ✅ **Native Performance** - Compiles to machine code, no runtime
- ✅ **3-Way Parameter Binding** - DAW ↔ Flutter UI ↔ Parameters stay in sync
- ✅ **Cross-Platform** - macOS, Windows, Linux support

## Installation

```yaml
dependencies:
  flutter_vst3:
    git:
      url: https://github.com/your-org/flutter_vst3_toolkit
      path: flutter_vst3
```

## Quick Start

### 1. Define Your Parameters

```dart
class MyParameters {
  /// Controls the output volume (0% = silence, 100% = full volume)
  double gain = 0.5;
  
  /// Adds warmth to the signal (0% = clean, 100% = saturated)  
  double warmth = 0.0;
  
  void setParameter(int paramId, double value) {
    switch (paramId) {
      case 0: gain = value; break;
      case 1: warmth = value; break;
    }
  }
}
```

### 2. Create Your Processor

```dart
import 'package:flutter_vst3/flutter_vst3.dart';

class MyProcessor extends VST3Processor {
  final parameters = MyParameters();
  
  @override
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR) {
    for (int i = 0; i < inputL.length; i++) {
      outputL[i] = inputL[i] * parameters.gain;
      outputR[i] = inputR[i] * parameters.gain;
    }
  }
  
  @override
  void setParameter(int paramId, double value) {
    parameters.setParameter(paramId, value);
  }
}
```

### 3. Build Flutter UI with Parameter Binding

```dart
import 'package:flutter/material.dart';
import 'package:flutter_vst3/flutter_vst3.dart';

class MyPluginUI extends StatefulWidget {
  @override
  _MyPluginUIState createState() => _MyPluginUIState();
}

class _MyPluginUIState extends State<MyPluginUI> {
  final parameters = MyParameters();
  
  @override
  void initState() {
    super.initState();
    // Register for DAW parameter changes
    VST3Bridge.registerParameterChangeCallback(_onParameterChanged);
  }
  
  void _onParameterChanged(int paramId, double value) {
    if (mounted) {
      setState(() => parameters.setParameter(paramId, value));
    }
  }
  
  void _updateParameter(int paramId, double value) {
    setState(() => parameters.setParameter(paramId, value));
    // Send to VST host/DAW
    VST3Bridge.sendParameterToHost(paramId, value);
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Slider(
              value: parameters.gain,
              onChanged: (v) => _updateParameter(0, v),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4. Build VST® 3 Plugin

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.20)
include(../../flutter_vst3/native/cmake/VST3Bridge.cmake)
add_dart_vst3_plugin(my_plugin my_parameters.dart)
```

```bash
mkdir build && cd build
cmake .. && make
# Output: my_plugin.vst3
```

## API Reference

### VST3Processor

Base class for all Dart VST® 3 processors:

```dart
abstract class VST3Processor {
  void initialize(double sampleRate, int maxBlockSize);
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR);
  void setParameter(int paramId, double normalizedValue);
  double getParameter(int paramId);
  int getParameterCount();
  void reset();
  void dispose();
}
```

### VST3Bridge

Main bridge for Flutter UI ↔ VST® host communication:

```dart
class VST3Bridge {
  // Register your processor
  static void registerProcessor(VST3Processor processor);
  
  // Parameter change notifications from DAW
  static void registerParameterChangeCallback(ParameterChangeCallback callback);
  
  // Send parameter changes to DAW
  static void sendParameterToHost(int paramId, double value);
}
```

## Examples

See the complete example plugins in the main repository:
- [Flutter Reverb](https://github.com/your-org/flutter_vst3_toolkit/tree/main/vsts/flutter_reverb) - Full reverb with Flutter UI
- [Echo Plugin](https://github.com/your-org/flutter_vst3_toolkit/tree/main/vsts/echo) - Delay/echo with custom knobs

## Requirements

- Dart SDK 3.0+
- Flutter SDK 3.0+
- CMake 3.20+
- Steinberg VST® 3 SDK
- C++17 compiler

## Legal Notice

This framework is not affiliated with Steinberg Media Technologies GmbH.
VST® is a trademark of Steinberg Media Technologies GmbH.

Users must comply with the Steinberg VST® 3 SDK License Agreement when distributing VST® 3 plugins.
See: https://steinbergmedia.github.io/vst3_dev_portal/pages/VST+3+Licensing/Index.html

## License

See LICENSE file in the repository root.