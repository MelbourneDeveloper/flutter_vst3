# dart_vst3_bridge - Zero C++ Required!

**THE C++ IS GONE!** 🎉

This bridge package now automatically generates ALL VST3 C++ boilerplate from your Dart parameter definitions. Plugin developers write ZERO C++ code.

## What Changed

### Before (Bad!)
- Plugins contained hand-written C++ files:
  - `src/reverb_controller.cpp` 
  - `src/reverb_processor.cpp`
  - `src/reverb_factory.cpp`
  - `include/reverb_ids.h`
- Developers had to maintain C++ code alongside Dart
- Parameter changes required updates in both languages

### After (Good!)
- Plugins contain ONLY Dart code:
  - `lib/src/plugin_parameters.dart` (parameter definitions)
  - `lib/src/plugin_processor.dart` (DSP logic)
- C++ files are auto-generated at build time from Dart definitions
- Single source of truth for all plugin metadata

## How It Works

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
   # Just specify your Dart parameter file!
   add_dart_vst3_plugin(flutter_reverb reverb_parameters.dart
       BUNDLE_IDENTIFIER "com.yourcompany.vst3.flutterreverb"
       COMPANY_NAME "Your Company"
       PLUGIN_NAME "Flutter Reverb"
   )
   ```

3. **Generated files** (completely hidden from user):
   - `generated/flutter_reverb_controller.cpp`
   - `generated/flutter_reverb_processor.cpp` 
   - `generated/flutter_reverb_factory.cpp`
   - `include/flutter_reverb_ids.h`

## Code Generation

The bridge uses a Dart script (`scripts/generate_plugin.dart`) that:

- Reads plugin metadata and parameters from JSON files  
- Generates complete VST3 C++ implementation
- Creates proper parameter handling, state management, and factory code  
- Maintains VST3 SDK compatibility
- Generates unique plugin UIDs based on name/company

### Generated Features

✅ **Parameter Management**: Automatic VST3 parameter registration  
✅ **State Persistence**: Save/load plugin state  
✅ **String Conversion**: Parameter value ↔ display string conversion  
✅ **Factory Registration**: Plugin discovery and instantiation  
✅ **Bundle Creation**: Complete .vst3 bundle with Info.plist  
✅ **Platform Support**: macOS, Windows, Linux  

## Usage

1. **Create parameter class** in `lib/src/your_plugin_parameters.dart`
2. **Add doc comments** describing each parameter
3. **Update CMakeLists.txt** to use `add_dart_vst3_plugin()`
4. **Build**: CMake automatically generates C++ and builds .vst3

```bash
cd vsts/your_plugin
mkdir build && cd build
cmake ..
make
# Output: your_plugin.vst3
```

## File Structure (After)

```
vsts/your_plugin/
├── lib/
│   ├── src/
│   │   ├── your_plugin_parameters.dart  ← ONLY USER FILE
│   │   └── your_plugin_processor.dart    ← DSP logic
│   └── your_plugin.dart
├── generated/                           ← AUTO-GENERATED (hidden)
│   ├── your_plugin_controller.cpp
│   ├── your_plugin_processor.cpp
│   └── your_plugin_factory.cpp
├── include/                             ← AUTO-GENERATED (hidden)
│   └── your_plugin_ids.h
├── CMakeLists.txt                       ← Simple, just specify Dart file
└── build/
    └── VST3/Release/your_plugin.vst3   ← Final output
```

## Benefits

🚀 **Zero C++ Knowledge Required**: Write only Dart  
🔧 **Single Source of Truth**: Parameters defined once in Dart  
⚡ **Automatic Updates**: C++ stays in sync with Dart changes  
🛡️ **Type Safety**: Generated C++ matches Dart exactly  
📦 **Complete VST3 Compliance**: Proper SDK integration  
🎯 **No Boilerplate**: Focus on DSP, not plumbing  

## Migration Guide

For existing plugins:

1. **Backup** existing C++ files (optional)
2. **Add doc comments** to Dart parameter classes  
3. **Update CMakeLists.txt** to use new function
4. **Delete** `src/` and `include/` directories
5. **Build** - C++ is auto-generated

The dart_vst3_bridge now delivers on its promise: **pure Dart VST3 development with zero C++ required!**