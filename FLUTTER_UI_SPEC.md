# Flutter VST3 UI Integration Specification

## Same Process/Isolate Execution
The Flutter UI and Dart audio processing code MUST execute in the SAME process and SAME Dart isolate. This is non-negotiable aspect of the design

The flutter_vst3 implementation compiles Dart to a separate native executable that communicates via binary IPC. This executable contains the Flutter UI. This process uses Binary IPC so that there is two way communication with C++. It is critical that all IPC is binary based.

The Dart/Flutter exe must compile to native machine code. Not JIT, no AOT.

## Communication

The Dart/Flutter exe communications with the C++ aspect of the plugin via binary IPC. Introduce a Dart framework to differentiate between audio signals over binary IPC and parameter changes etc. 

## Architecture 

Dart/Flutter exe (Audio Processing AND UI) -> C++ -> DAW
DAW -> C++ -> Dart/Flutter exe (Audio Processing AND UI)

Note: the communication between Dart/Flutter exe and C++ is Binary IPC!!!