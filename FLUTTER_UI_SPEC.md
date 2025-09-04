# Flutter VST3 UI Integration Specification

## Core Architecture Requirements

### CRITICAL: Same Process/Isolate Execution
**The Flutter UI and Dart audio processing code MUST execute in the SAME process and SAME Dart isolate.** This is non-negotiable for proper VST3 integration.

## Current Problem

The existing flutter_vst3 implementation compiles Dart to a separate native executable that communicates via stdin/stdout. This architecture is fundamentally broken for UI integration because:

1. UI and audio run in separate processes
2. No shared memory for parameters
3. Cannot implement proper IPlugView
4. No way to achieve real-time parameter binding

## Required Solution

### 1. Embedded Flutter Runtime

Replace the native executable approach with an embedded Flutter runtime that runs inside the VST3 plugin process:

```cpp
// plugin_flutter_view.cpp
class PluginFlutterView : public IPlugView, public IParameterObserver {
private:
    // Single Flutter engine per plugin instance
    FlutterEngine* engine;
    
    // Shared parameter state - accessed by BOTH audio and UI
    ParameterState* sharedParams;
    
    // Platform view handle
    void* nativeView;
    
public:
    tresult attached(void* parent, FIDString type) override {
        // Initialize Flutter engine IN THIS PROCESS
        engine = flutter::CreateEngine({
            .dart_entrypoint = "main",
            .dart_entrypoint_library = "package:plugin/main.dart",
        });
        
        // Create platform view
        nativeView = CreatePlatformView(parent, type);
        
        // Attach Flutter rendering to platform view
        engine->AttachToView(nativeView);
        
        // Register parameter binding channels
        RegisterParameterBinding(engine, sharedParams);
        
        return kResultTrue;
    }
};
```

### 2. Shared Parameter Architecture

Parameters MUST be in the SAME isolate and SAME process:

```cpp
// Shared parameter state - accessed by both threads
struct ParameterState {
    std::atomic<double> values[MAX_PARAMS];
    
    // Thread-safe parameter update from UI
    void setFromUI(int id, double value) {
        values[id].store(value, std::memory_order_relaxed);
        notifyProcessor();
    }
    
    // Lock-free read from audio thread
    double getForAudio(int id) const {
        return values[id].load(std::memory_order_relaxed);
    }
};
```

### 3. Dart FFI for Audio Processing

Audio processing happens via FFI in the SAME Dart isolate as the UI:

```dart
// plugin_processor.dart
import 'dart:ffi';
import 'package:flutter/services.dart';

class PluginProcessor {
  // Shared parameter binding
  static final _paramChannel = MethodChannel('vst3/parameters');
  
  // FFI entry point - called from C++ audio thread
  @pragma('vm:entry-point')
  static void processAudio(Pointer<Float> inputL, Pointer<Float> inputR,
                          Pointer<Float> outputL, Pointer<Float> outputR,
                          int samples) {
    // Audio processing happens here in Dart
    // This runs in the SAME isolate as the Flutter UI
    for (int i = 0; i < samples; i++) {
      outputL[i] = inputL[i] * _currentGain;
      outputR[i] = inputR[i] * _currentGain;
    }
  }
  
  // Parameter update from UI
  static void updateParameter(int id, double value) {
    _paramChannel.invokeMethod('setParameter', {'id': id, 'value': value});
  }
}
```

### 4. Flutter UI with Parameter Binding

```dart
// plugin_ui.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PluginUI extends StatefulWidget {
  @override
  _PluginUIState createState() => _PluginUIState();
}

class _PluginUIState extends State<PluginUI> {
  static const _channel = MethodChannel('vst3/parameters');
  Map<int, double> _parameters = {};
  
  @override
  void initState() {
    super.initState();
    
    // Listen for parameter changes from DAW
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'parameterChanged') {
        setState(() {
          _parameters[call.arguments['id']] = call.arguments['value'];
        });
      }
    });
  }
  
  // Update parameter from UI
  void _updateParameter(int id, double value) {
    setState(() {
      _parameters[id] = value;
    });
    
    // Send to audio processor (same process!)
    _channel.invokeMethod('setParameter', {'id': id, 'value': value});
  }
}
```

## Implementation Architecture

### Build System Changes

The CMake build must:
1. Embed Flutter engine libraries
2. Compile Dart UI and audio together
3. Generate FFI bindings
4. Link everything into single VST3 bundle

```cmake
# VST3Bridge.cmake modifications
function(add_dart_vst3_plugin target_name dart_params_file)
    # Find Flutter SDK
    find_package(Flutter REQUIRED)
    
    # Compile Dart to kernel snapshot (NOT native executable!)
    add_custom_command(
        OUTPUT ${target_name}_kernel.dill
        COMMAND ${DART_EXECUTABLE} compile kernel
                ${CMAKE_CURRENT_SOURCE_DIR}/lib/main.dart
                -o ${CMAKE_CURRENT_BINARY_DIR}/${target_name}_kernel.dill
    )
    
    # Create VST3 plugin with embedded Flutter
    add_library(${target_name} MODULE
        ${GENERATED_SOURCES}
        flutter_view.cpp
        parameter_bridge.cpp
        audio_ffi.cpp
    )
    
    # Link Flutter engine
    target_link_libraries(${target_name}
        flutter_engine
        flutter_embedder
        sdk
    )
endfunction()
```

### Thread Architecture

```
VST3 Plugin Process
├── Main Thread (UI)
│   ├── Flutter Engine
│   ├── Flutter UI Widgets
│   └── Parameter Method Channel
│
├── Audio Thread (Real-time)
│   ├── VST3 Process Callback
│   ├── FFI Call to Dart
│   └── Dart Audio Processing
│
└── Shared Memory
    └── Atomic Parameter Values
```

### Parameter Flow

1. **UI → Audio:**
   - User moves slider in Flutter UI
   - MethodChannel sends parameter update
   - C++ updates atomic parameter value
   - Audio thread reads new value

2. **DAW → UI:**
   - DAW automation changes parameter
   - C++ parameter observer notified
   - MethodChannel sends update to Flutter
   - UI rebuilds with new value

3. **Same Process Guarantees:**
   - Shared memory for parameters
   - Direct FFI calls for audio
   - No IPC overhead
   - Real-time safe operation

## Critical Implementation Details

### 1. Flutter Engine Lifecycle
- Initialize once per plugin instance
- Keep engine alive for plugin lifetime
- Proper cleanup on plugin destruction

### 2. Thread Safety
- Use atomics for parameter values
- No locks in audio thread
- Message passing for UI updates

### 3. Platform Integration
- NSView for macOS
- HWND for Windows  
- X11 for Linux
- Each requires platform-specific view setup

### 4. Memory Management
- RAII for all resources
- No memory allocations in audio callback
- Pre-allocated buffers for FFI

## File Structure

```
flutter_vst3/
├── native/
│   ├── cmake/
│   │   └── VST3Bridge.cmake      # Modified for Flutter embedding
│   ├── src/
│   │   ├── flutter_view.cpp      # IPlugView implementation
│   │   ├── parameter_bridge.cpp  # Parameter synchronization
│   │   └── audio_ffi.cpp         # FFI audio processing
│   └── include/
│       └── flutter_vst3.h        # Public API
│
├── lib/
│   ├── src/
│   │   ├── parameter_binding.dart # Parameter synchronization
│   │   ├── audio_processor.dart   # Base audio processor
│   │   └── ui_framework.dart      # UI widget framework
│   └── flutter_vst3.dart          # Public API
│
└── scripts/
    └── generate_plugin.dart       # Code generator
```

## Migration Path for Existing Plugins

1. Replace `*_processor_exe.dart` with FFI entry points
2. Add Flutter UI entry point in `lib/main.dart`
3. Update CMakeLists.txt to use new build function
4. Implement parameter binding in UI

## Success Metrics

- ✅ Flutter UI and Dart audio in SAME process
- ✅ Parameter changes reflect immediately in both directions
- ✅ No subprocess communication
- ✅ Real-time safe audio processing
- ✅ Works in all major DAWs

## Conclusion

This architecture ensures Flutter UI and Dart audio processing run in the SAME process with proper VST3 integration. The key is embedding the Flutter engine directly in the VST3 plugin and using FFI for audio processing within the same Dart isolate.