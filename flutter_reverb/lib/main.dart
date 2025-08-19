/// Main entry point for Flutter Dart Reverb VST3 plugin
/// 
/// This file provides the entry point that registers the reverb processor
/// with the VST3 bridge, enabling the pure Dart reverb processor to be
/// called from the VST3 plugin.

import 'package:dart_vst3_bridge/dart_vst3_bridge.dart';
import 'src/reverb_vst3_processor.dart';
import 'src/reverb_ui.dart';

/// Initialize the Flutter Dart Reverb plugin
/// This must be called when the VST3 plugin is loaded to register
/// the Dart processor with the VST3 bridge
void main() {
  // Register the reverb processor with the VST3 bridge
  VST3Bridge.registerProcessor(ReverbVST3Processor());
  
  // Register VST3 callbacks with C++ layer
  registerVST3Callbacks();
}

/// Entry point called from C++ when VST3 plugin initializes
/// This ensures the Dart VM and processor are properly set up
void initializeDartReverb() {
  main();
}

/// CLI entry point for testing
void runCLI() {
  final cli = ReverbCLI();
  cli.run();
}