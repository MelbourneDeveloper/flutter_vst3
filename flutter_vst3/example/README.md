# flutter_vst3 Example

For comprehensive examples of VST® 3 plugin development with flutter_vst3, please see the complete plugin implementations in the main repository:

- [Flutter Reverb Plugin](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/vsts/flutter_reverb) - A full reverb plugin with Flutter UI
- [Echo Plugin](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/vsts/echo) - A delay/echo plugin with custom controls

## Quick Start

Follow the [Complete Step-by-Step Plugin Creation Guide](../create_plugin_guide.md) to create your first VST® 3 plugin.

## Basic Plugin Structure

```dart
import 'package:flutter_vst3/flutter_vst3.dart';

class MyProcessor extends VST3Processor {
  @override
  void initialize(double sampleRate, int maxBlockSize) {
    // Initialize your audio processing
  }

  @override
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR) {
    // Your audio processing logic here
    for (int i = 0; i < inputL.length; i++) {
      outputL[i] = inputL[i]; // Pass through for now
      outputR[i] = inputR[i];
    }
  }
}
```

*VST® is a registered trademark of Steinberg Media Technologies GmbH, registered in Europe and other countries.*