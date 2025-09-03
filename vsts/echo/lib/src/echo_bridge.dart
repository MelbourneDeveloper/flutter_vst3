import 'package:dart_vst3_bridge/dart_vst3_bridge.dart';
import 'echo_vst3_processor.dart';

/// FFI bindings for the echo VST3 bridge - FAILS HARD if callbacks not registered
class EchoBridge {
  static EchoVST3Processor? _processor;
  
  /// Initialize the bridge and register callbacks
  static void initialize() {
    // Create the processor
    _processor = EchoVST3Processor();
    
    // Register with the global VST3 bridge
    VST3Bridge.registerProcessor(_processor!);
    
    print('Echo bridge initialized with callbacks registered');
  }

  /// Get the registered processor (for testing)
  static EchoVST3Processor? getProcessor() => _processor;
}