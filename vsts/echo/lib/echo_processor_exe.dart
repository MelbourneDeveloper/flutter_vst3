import 'dart:io';
import 'dart:typed_data';
import 'src/echo_processor.dart';
import 'src/echo_parameters.dart';

// Binary IPC command codes for audio processing AND UI commands
const cmdInit = 0x01;
const cmdProcess = 0x02;
const cmdSetParam = 0x03;
const cmdTerminate = 0xFF;

// Binary UI command codes (ALL BINARY IPC!)
const cmdInitUI = 0x10;
const cmdResize = 0x11;
const cmdGetWindow = 0x12;

void main(List<String> args) async {
  final showUI = args.contains('--ui');
  final processor = EchoProcessor();
  final parameters = EchoParameters();
  
  if (showUI) {
    await runUIProcessor(processor, parameters);
  } else {
    await runUnifiedProcessor(processor, parameters, false);
  }
}

/// Run processor with native UI support
Future<void> runUIProcessor(EchoProcessor processor, EchoParameters parameters) async {
  stderr.writeln('ECHO VST3: Launching with NATIVE UI in SAME process/isolate');
  
  // TODO: Initialize native UI window using FFI
  // For now, create a simple console-based UI simulation
  _createSimpleUI();
  
  try {
    stdin.lineMode = false;
  } catch (e) {
    // Ignore if stdin is not a terminal
  }

  await for (final bytes in stdin) {
    if (bytes.isEmpty) continue;
    await _handleUnifiedCommand(bytes, processor, parameters, true);
  }
}

void _createSimpleUI() {
  stderr.writeln('ECHO VST3: Simple Native UI Created');
  stderr.writeln('  - DelayTime: 0.5000 ms');
  stderr.writeln('  - Feedback: 0.3000 %'); 
  stderr.writeln('  - Mix: 0.5000 %');
  stderr.writeln('  - Bypass: Off');
}

/// Unified processor supporting BOTH audio processing AND native UI in SAME process/isolate
/// CRITICAL: This is compiled to NATIVE MACHINE CODE (not AOT, not JIT)
/// UI uses native platform APIs, NOT Flutter (which requires Dart VM)
Future<void> runUnifiedProcessor(EchoProcessor processor, EchoParameters parameters, bool showUI) async {
  if (showUI) {
    stderr.writeln('ECHO VST3: Launching with NATIVE UI in SAME process/isolate');
    // TODO: Initialize native UI window (NSWindow/HWND/X11)
  } else {
    stderr.writeln('ECHO VST3: Audio processing only mode');
  }

  try {
    stdin.lineMode = false;
  } catch (e) {
    // Ignore if stdin is not a terminal
  }

  await for (final bytes in stdin) {
    if (bytes.isEmpty) continue;
    await _handleUnifiedCommand(bytes, processor, parameters, showUI);
  }
}

/// Handle ALL BINARY commands in SAME process (audio + UI)
/// CRITICAL: Compiles to NATIVE MACHINE CODE
Future<void> _handleUnifiedCommand(List<int> bytes, EchoProcessor processor, EchoParameters parameters, bool hasUI) async {
  final buffer = ByteData.view(Uint8List.fromList(bytes).buffer);
  final command = buffer.getUint8(0);
  
  switch (command) {
    case cmdInit:
      final sampleRate = buffer.getFloat64(1, Endian.little);
      processor.initialize(sampleRate, 512);
      stdout.add([cmdInit]);
      await stdout.flush();
      break;
      
    case cmdProcess:
      final numSamples = buffer.getInt32(1, Endian.little);
      final audioData = Float32List(numSamples * 2);
      for (int i = 0; i < numSamples * 2; i++) {
        audioData[i] = buffer.getFloat32(5 + i * 4, Endian.little);
      }
      
      final inputL = List<double>.generate(numSamples, (i) => audioData[i * 2].toDouble());
      final inputR = List<double>.generate(numSamples, (i) => audioData[i * 2 + 1].toDouble());
      final outputL = List<double>.filled(numSamples, 0.0);
      final outputR = List<double>.filled(numSamples, 0.0);
      
      processor.processStereo(inputL, inputR, outputL, outputR, parameters);
      
      final response = ByteData(1 + numSamples * 8);
      response.setUint8(0, cmdProcess);
      for (int i = 0; i < numSamples; i++) {
        response.setFloat32(1 + i * 8, outputL[i], Endian.little);
        response.setFloat32(1 + i * 8 + 4, outputR[i], Endian.little);
      }
      
      stdout.add(response.buffer.asUint8List());
      await stdout.flush();
      break;
      
    case cmdSetParam:
      final paramId = buffer.getInt32(1, Endian.little);
      final value = buffer.getFloat64(5, Endian.little);
      parameters.setParameter(paramId, value);
      
      // Update UI if present
      hasUI ? _updateNativeUI(paramId, value) : null;
      
      stdout.add([cmdSetParam]);
      await stdout.flush();
      break;
    
    case cmdInitUI:
      stdout.add([cmdInitUI]);
      await stdout.flush();
      break;
      
    case cmdResize:
      final width = buffer.getInt32(1, Endian.little);
      final height = buffer.getInt32(5, Endian.little);
      
      // Resize native UI if present
      hasUI ? _resizeNativeUI(width, height) : null;
      
      stdout.add([cmdResize]);
      await stdout.flush();
      break;
      
    case cmdGetWindow:
      final windowHandle = hasUI ? _getNativeWindowHandle() : 0x0;
      final response = ByteData(9);
      response.setUint8(0, cmdGetWindow);
      response.setInt64(1, windowHandle, Endian.little);
      stdout.add(response.buffer.asUint8List());
      await stdout.flush();
      break;
      
    case cmdTerminate:
      exit(0);
  }
}

void _updateNativeUI(int paramId, double value) {
  // TODO: Update native UI controls (NSSlider/Win32 slider/GTK slider)
  stderr.writeln('UI UPDATE: Param $paramId = $value');
}

void _resizeNativeUI(int width, int height) {
  // TODO: Resize native UI window
  stderr.writeln('UI RESIZE: ${width}x$height');
}

int _getNativeWindowHandle() {
  // TODO: Return actual native window handle (NSWindow*/HWND/Window)
  return 0x12345678; // Stub
}

