# Dart VST3 Toolkit

**A comprehensive toolkit for building VST3 plugins and hosts in pure Dart and Flutter.**

This is first and foremost a toolkit for creating VST3 plugins and VST hosts using Dart and Flutter. The toolkit enables developers to build professional audio plugins with modern UI frameworks while leveraging the power of the VST3 ecosystem.

## Architecture Overview

```mermaid
graph TB
    subgraph "DAW Integration"
        DAW1[Ableton Live]
        DAW2[FL Studio]
        DAW3[Reaper]
        DAW4[Other VST3 Hosts]
    end
    
    subgraph "Dart VST3 Toolkit"
        subgraph "VST Creation"
            FR[flutter_reverb<br/>Pure Dart VST]
            DVST[dart_vst_creator<br/>VST Building Tools]
        end
        
        subgraph "VST Hosting"
            DVH[dart_vst_host<br/>Load & Control VSTs]
            DVG[dart_vst_graph<br/>Audio Routing & Mixing]
        end
        
        subgraph "Native Bridge"
            NL[native/<br/>C++ VST3 Implementation]
            PL[plugin/<br/>VST3 Plugin Wrapper]
        end
        
        subgraph "UI Layer"
            FUI[flutter_ui<br/>Desktop Host App]
        end
    end
    
    subgraph "External VSTs"
        VST1[TAL Reverb]
        VST2[Other VST3s]
    end
    
    %% VST Creation Flow
    FR --> DVST
    DVST --> PL
    PL --> NL
    
    %% VST Hosting Flow  
    VST1 --> DVH
    VST2 --> DVH
    DVH --> DVG
    DVG --> NL
    
    %% UI Integration
    FUI --> DVH
    FUI --> DVG
    
    %% DAW Integration
    NL --> DAW1
    NL --> DAW2
    NL --> DAW3
    NL --> DAW4
    
    style FR fill:#e1f5fe
    style DVST fill:#e1f5fe
    style DVH fill:#fff3e0
    style DVG fill:#fff3e0
    style NL fill:#f3e5f5
    style PL fill:#f3e5f5
```

## Package Overview

### 🎛️ VST3 Plugin Creation

**Primary Purpose: Build actual VST3 plugins using Dart/Flutter that compile to .vst3 bundles**

- **`flutter_reverb`** - Complete VST3 reverb plugin implementation in pure Dart, compiles via existing C++/VST3 SDK infrastructure to actual .vst3 bundle
- **`plugin/`** - C++ VST3 wrapper using Steinberg SDK that hosts Dart code via FFI interop layer
- **`native/`** - C++ infrastructure providing the bridge between VST3 API and Dart audio processing

### 🎧 VST Hosting Packages  

**Primary Purpose: Load and control existing VST3 plugins from Dart applications**

- **`dart_vst_host`** - High-level API for loading and controlling VST3 plugins
- **`dart_vst_graph`** - Audio graph system for routing and mixing VST plugins with built-in nodes (mixers, splitters, gain)

### 🔧 Native Infrastructure

- **`native/`** - C++ implementation using Steinberg VST3 SDK
- **`plugin/`** - VST3 plugin wrapper that hosts the Dart audio graph
- **`flutter_ui/`** - Desktop Flutter application for interactive testing

## Use Cases

### 1. Creating VST3 Plugins in Dart/Flutter

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant FR as flutter_reverb
    participant CPP as plugin/ (C++ VST3)
    participant SDK as VST3 SDK
    participant DAW as DAW

    Dev->>FR: Write audio processing in pure Dart
    Dev->>CPP: C++ wrapper implements VST3 interfaces
    CPP->>SDK: Uses Steinberg VST3 SDK
    CPP->>FR: FFI interop layer calls Dart code
    SDK->>CPP: Compile to .vst3 bundle
    CPP->>DAW: DAW loads .vst3 bundle
    DAW->>CPP: Process audio (VST3 API)
    CPP->>FR: Route to Dart processor via FFI
    FR->>CPP: Return processed audio
    CPP->>DAW: Return audio via VST3 API
```

### 2. Building VST Host Applications

```mermaid
sequenceDiagram
    participant App as Your Dart App
    participant DVH as dart_vst_host
    participant DVG as dart_vst_graph
    participant VST as External VST3

    App->>DVH: Load VST3 plugin
    App->>DVG: Create audio graph
    DVG->>VST: Route audio through plugin
    VST->>DVG: Return processed audio
    DVG->>App: Mixed output
```

### 3. DAW Integration Examples

#### Ableton Live Workflow
```mermaid
graph LR
    subgraph "Ableton Live"
        TR1[Audio Track 1]
        TR2[Audio Track 2] 
        TR3[Return Track]
    end
    
    subgraph "Dart VST Plugin"
        UI[Flutter UI]
        PROC[Dart Audio Processor]
    end
    
    TR1 --> PROC
    TR2 --> PROC
    PROC --> TR3
    PROC <--> UI
```

#### FL Studio Integration  
```mermaid
graph TB
    subgraph "FL Studio Mixer"
        CH1[Channel 1]
        CH2[Channel 2]
        SEND[Send Channel]
    end
    
    subgraph "Your Dart VST"
        DART[Dart Reverb Plugin]
        FLU[Flutter Control Panel]
    end
    
    CH1 --> DART
    CH2 --> DART
    DART --> SEND
    FLU <--> DART
```

## Quick Start

### Prerequisites

```bash
# Set VST3 SDK path
export VST3_SDK_DIR=/path/to/vst3sdk

# Install dependencies
flutter pub get
dart pub get
```

### Building Your First VST Plugin

1. **Study the reference implementation:**
```bash
cd flutter_reverb/
flutter run example/demo.dart
```

2. **Build the native infrastructure:**
```bash
cd native/
mkdir build && cd build
cmake ..
make
```

3. **Create VST3 bundle:**
```bash
cd plugin/
mkdir build && cd build  
cmake ..
make
# Output: your_plugin.vst3
```

### Building a VST Host Application

```dart
import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:dart_vst_graph/dart_vst_graph.dart';

void main() async {
  // Initialize host
  final host = VstHost();
  await host.initialize();
  
  // Load VST plugin
  final plugin = await host.loadPlugin('path/to/plugin.vst3');
  
  // Create audio graph
  final graph = VstGraph();
  final pluginNode = graph.addVstNode(plugin);
  final mixerNode = graph.addMixerNode();
  
  // Connect nodes
  graph.connect(pluginNode.output, mixerNode.input1);
  
  // Start processing
  await graph.start();
}
```

## Project Structure

```
dart_vst_toolkit/
├── flutter_reverb/         # Reference VST implementation  
├── dart_vst_host/          # VST hosting API
├── dart_vst_graph/         # Audio graph system
├── native/                 # C++ VST3 implementation
├── plugin/                 # VST3 plugin wrapper
├── flutter_ui/             # GUI host application
└── vst_plugins/            # External VST3 plugins for testing
```

## Development Workflow

### 1. VST Plugin Development
1. Implement audio processing in `flutter_reverb/lib/src/reverb_processor.dart`
2. Design UI in `flutter_reverb/lib/src/reverb_ui.dart`  
3. Test with Flutter: `flutter run`
4. Build VST3: `make -C plugin/build`
5. Test in DAW

### 2. Host Application Development
1. Build native library: `make -C native/build`
2. Implement in Dart using `dart_vst_host` and `dart_vst_graph`
3. Test with Flutter UI: `flutter run -d desktop`

## Testing

**All packages:**
```bash
# Build native dependencies first
cd native/ && mkdir build && cd build && cmake .. && make

# Test Dart packages
cd dart_vst_host/ && dart test
cd dart_vst_graph/ && dart test
cd flutter_reverb/ && dart test
```

**Integration testing:**
```bash
cd flutter_ui/
flutter run  # Interactive testing with GUI
```

## Key Features

### For VST Plugin Creators
- ✅ Pure Dart/Flutter audio processing
- ✅ Modern Flutter UI framework
- ✅ Hot reload during development
- ✅ Cross-platform VST3 output
- ✅ Parameter automation
- ✅ State persistence

### For VST Host Developers  
- ✅ Load any VST3 plugin
- ✅ Flexible audio routing
- ✅ Built-in mixing nodes
- ✅ Real-time parameter control
- ✅ RAII resource management
- ✅ Flutter UI integration

### Platform Support
- ✅ **macOS**: `.dylib` + `.vst3` bundle
- ✅ **Linux**: `.so` library
- ✅ **Windows**: `.dll` library *(coming soon)*

## Examples in the Wild

### Creating Reverb VST
```dart
// flutter_reverb/lib/src/reverb_processor.dart
class ReverbProcessor {
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR) {
    // Your reverb algorithm here
    for (int i = 0; i < inputL.length; i++) {
      outputL[i] = inputL[i] * wetLevel + reverbL * dryLevel;
      outputR[i] = inputR[i] * wetLevel + reverbR * dryLevel;
    }
  }
}
```

### Loading VSTs in Your App
```dart
// Using dart_vst_host
final plugin = await host.loadPlugin('/path/to/TAL-Reverb-4.vst3');
plugin.setParameter(0, 0.75); // Set room size
final processedAudio = plugin.processAudio(inputBuffer);
```

### Building Audio Graphs
```dart  
// Using dart_vst_graph
final graph = VstGraph();
final reverb = graph.addVstNode(reverbPlugin);
final delay = graph.addVstNode(delayPlugin);
final mixer = graph.addMixerNode();

// Chain: input -> reverb -> delay -> mixer -> output
graph.connect(graph.input, reverb.input);
graph.connect(reverb.output, delay.input);
graph.connect(delay.output, mixer.input1);
graph.connect(mixer.output, graph.output);
```

## Contributing

This toolkit is designed for professional audio development. Contributions should maintain:

- **No duplication**: Use existing components, don't recreate them
- **No placeholders**: Implementation must be complete and functional  
- **Pure FP style**: Immutable data, pure functions
- **Comprehensive testing**: Tests must fail hard, no warnings
- **Clear documentation**: All public APIs documented

## License

This project uses the Steinberg VST3 SDK. Please review the VST3 License Agreement before commercial use.

---

**Ready to build the next generation of audio plugins with Dart and Flutter? Start with `flutter_reverb` and explore the examples!**