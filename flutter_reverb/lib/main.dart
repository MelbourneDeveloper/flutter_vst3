/// Main entry point for Flutter Dart Reverb VST3 plugin
/// 
/// This file provides the entry point that registers Dart callbacks
/// with the C++ VST3 infrastructure, enabling the pure Dart reverb
/// processor to be called from the VST3 plugin.

import 'src/ffi_bridge.dart';
import 'src/reverb_ui.dart';

/// Initialize the Flutter Dart Reverb plugin
/// This must be called when the VST3 plugin is loaded to register
/// the Dart callback functions with the C++ layer
void main() {
  registerDartCallbacks();
}

/// Entry point called from C++ when VST3 plugin initializes
/// This ensures the Dart VM and callbacks are properly set up
void initializeDartReverb() {
  registerDartCallbacks();
}

/// CLI entry point for testing
void runCLI() {
  final cli = ReverbCLI();
  cli.run();
}