# flutter_vst3 Example

For comprehensive examples of VST® 3 plugin development with flutter_vst3, please see the complete plugin implementations in the main repository:

- [Flutter Reverb Plugin](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/vsts/flutter_reverb) - A full reverb plugin with Flutter UI
- [Echo Plugin](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/vsts/echo) - A delay/echo plugin with custom controls

## Quick Start

Follow the [Complete Step-by-Step Plugin Creation Guide](../create_plugin_guide.md) to create your first VST® 3 plugin.

## Basic Plugin Structure

```dart
import 'dart:typed_data';
import 'package:flutter_vst3/flutter_vst3.dart';

final class MyProcessor implements Vst3WorkerProcessor {
  @override
  void initialize(double sampleRate, int maxBlockSize) {}

  @override
  void setParameter(int paramId, double value) {}

  @override
  void processStereo(Float32List inputL, Float32List inputR,
      Float32List outputL, Float32List outputR) {
    outputL.setAll(0, inputL);
    outputR.setAll(0, inputR);
  }

  @override
  void reset() {}

  @override
  void dispose() {}
}

void main(List<String> args) {
  runVst3SharedMemoryProcessor(args: args, processor: MyProcessor());
}
```

*VST® is a registered trademark of Steinberg Media Technologies GmbH, registered in Europe and other countries.*