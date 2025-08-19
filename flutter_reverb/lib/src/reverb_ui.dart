import 'dart:math' as math;
import 'reverb_plugin.dart';
import 'reverb_parameters.dart';

/// Pure Dart UI controller for the unified Dart Reverb Plugin
/// This provides a programmatic interface without Flutter dependencies
class ReverbUIController {
  final DartReverbPlugin? plugin;
  
  late DartReverbPlugin _plugin;
  bool _isInitialized = false;

  ReverbUIController({this.plugin}) {
    _plugin = plugin ?? DartReverbPlugin();
    _initializePlugin();
  }

  void _initializePlugin() {
    final success = _plugin.initialize();
    _isInitialized = success;
    
    if (success) {
      _plugin.setupProcessing(44100.0, 1024);
      _plugin.setActive(true);
      print('✓ Reverb plugin initialized successfully');
    } else {
      print('✗ Failed to initialize reverb plugin');
    }
  }

  /// Update a parameter value
  void updateParameter(int paramId, double value) {
    if (_isInitialized) {
      _plugin.setParameter(paramId, value);
      final paramName = _plugin.getParameterInfo(paramId).name;
      print('Updated $paramName: ${(value * 100).toStringAsFixed(1)}%');
    }
  }

  /// Test the reverb processing
  void testReverb() {
    if (!_isInitialized) {
      print('Plugin not initialized');
      return;
    }
    
    try {
      print('Testing reverb processing...');
      
      // Generate test audio
      const numSamples = 1000;
      final testSignalL = List.generate(numSamples, (i) => 
          math.sin(i * 2 * math.pi * 440 / 44100) * 0.5);
      final testSignalR = List.generate(numSamples, (i) => 
          math.sin(i * 2 * math.pi * 440 / 44100) * 0.5);
      
      final outputL = List<double>.filled(numSamples, 0.0);
      final outputR = List<double>.filled(numSamples, 0.0);
      
      _plugin.processAudio([testSignalL, testSignalR], [outputL, outputR]);
      
      print('✓ Processed $numSamples samples through pure Dart reverb');
      
      // Show some sample values
      print('First 3 samples: ${testSignalL.take(3).map((v) => v.toStringAsFixed(4)).join(', ')}');
      print('Output samples:  ${outputL.take(3).map((v) => v.toStringAsFixed(4)).join(', ')}');
      
    } catch (e) {
      print('✗ Error processing audio: $e');
    }
  }

  /// Get current parameter values
  Map<String, double> getCurrentParameters() {
    if (!_isInitialized) return {};
    
    return {
      'roomSize': _plugin.getParameter(ReverbParameters.kRoomSizeParam),
      'damping': _plugin.getParameter(ReverbParameters.kDampingParam),
      'wetLevel': _plugin.getParameter(ReverbParameters.kWetLevelParam),
      'dryLevel': _plugin.getParameter(ReverbParameters.kDryLevelParam),
    };
  }

  /// Print plugin status
  void printStatus() {
    print('\n=== Plugin Status ===');
    print('Initialized: $_isInitialized');
    if (_isInitialized) {
      print('Name: ${DartReverbPlugin.pluginName}');
      print('Vendor: ${DartReverbPlugin.vendor}');
      print('Version: ${DartReverbPlugin.version}');
      print('Parameters: ${_plugin.parameterCount}');
      
      print('\nCurrent Parameters:');
      final params = getCurrentParameters();
      params.forEach((name, value) {
        print('  $name: ${(value * 100).toStringAsFixed(1)}%');
      });
    }
  }

  /// Dispose resources
  void dispose() {
    if (_isInitialized) {
      _plugin.setActive(false);
      _plugin.dispose();
      print('✓ Plugin disposed');
    }
  }
}

/// Simple command-line interface for the reverb plugin
class ReverbCLI {
  late ReverbUIController _controller;
  
  ReverbCLI() {
    _controller = ReverbUIController();
  }

  /// Run the interactive CLI
  void run() {
    print('=== Pure Dart Reverb Plugin CLI ===\n');
    
    _controller.printStatus();
    
    // Test with different settings
    print('\n=== Testing Different Settings ===');
    
    // Test 1: Small room, low wet
    print('\nTest 1: Small room, low reverb');
    _controller.updateParameter(ReverbParameters.kRoomSizeParam, 0.2);
    _controller.updateParameter(ReverbParameters.kWetLevelParam, 0.1);
    _controller.testReverb();
    
    // Test 2: Large room, high wet
    print('\nTest 2: Large room, high reverb');
    _controller.updateParameter(ReverbParameters.kRoomSizeParam, 0.9);
    _controller.updateParameter(ReverbParameters.kWetLevelParam, 0.8);
    _controller.testReverb();
    
    // Test 3: Medium settings
    print('\nTest 3: Medium settings');
    _controller.updateParameter(ReverbParameters.kRoomSizeParam, 0.5);
    _controller.updateParameter(ReverbParameters.kWetLevelParam, 0.4);
    _controller.updateParameter(ReverbParameters.kDampingParam, 0.3);
    _controller.testReverb();
    
    _controller.printStatus();
    _controller.dispose();
    
    print('\n✅ CLI demo completed successfully!');
  }
}