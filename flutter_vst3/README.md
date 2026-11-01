# flutter_vst3

Flutter/Dart framework for building VST® 3 plugins with Flutter UI and pure Dart audio processing.

<img src="https://github.com/MelbourneDeveloper/flutter_vst3/raw/main/flutter_vst3/VST_Compatible_Logo_Steinberg.png" alt="VST Compatible" width="100">

*VST® is a registered trademark of Steinberg Media Technologies GmbH, registered in Europe and other countries.*

## Overview

`flutter_vst3` is a complete framework that enables you to build professional VST® 3 audio plugins using Flutter for the UI and Dart for real-time audio processing. The framework auto-generates all C++ VST® 3 boilerplate code - you write only Dart and Flutter.

**For complete architecture documentation and examples, see the [main project README](https://github.com/MelbourneDeveloper/flutter_vst3).**

## Features

- ✅ **Flutter UI** - Build beautiful, reactive plugin interfaces
- ✅ **Pure Dart DSP** - Write audio processing in familiar Dart syntax
- ✅ **Auto-Generated C++** - Never write VST® 3 boilerplate
- ✅ **Native Performance** - Compiles to machine code, no runtime
- ✅ **3-Way Parameter Binding** - DAW ↔ Flutter UI ↔ Parameters stay in sync
- ✅ **Cross-Platform** - macOS, Windows, Linux support

## Quick Start

📖 **[Complete Step-by-Step Plugin Creation Guide](create_plugin_guide.md)**

The guide covers everything you need to build your first VST® 3 plugin:
- Project setup and dependencies
- Parameter definition with auto-generated C++
- Building and testing your plugin
- Installation to system VST® 3 directory

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
  
  // Initialize processor (called from C++ layer)
  static void initializeProcessor(double sampleRate, int maxBlockSize);
  
  // Process audio (called from C++ layer)
  static void processStereoCallback(/* FFI parameters */);
}
```

## Examples

See the complete example plugins in the main repository:
- [Flutter Reverb](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/vsts/flutter_reverb) - Full reverb with Flutter UI
- [Echo Plugin](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/vsts/echo) - Delay/echo with custom knobs

## Requirements

- Dart SDK 3.0+
- Flutter SDK 3.0+
- CMake 3.20+
- Steinberg VST® 3 SDK
- C++17 compiler
- Linux: X11 backend required for VST3 plugin GUI (launch with `GDK_BACKEND=x11 flutter run`)

## Legal Notice

This framework is not affiliated with Steinberg Media Technologies GmbH.
VST® is a trademark of Steinberg Media Technologies GmbH.

Users must comply with the Steinberg VST® 3 SDK License Agreement when distributing VST® 3 plugins.
See: https://steinbergmedia.github.io/vst3_dev_portal/pages/VST+3+Licensing/Index.html

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.