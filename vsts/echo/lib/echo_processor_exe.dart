import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'src/echo_processor.dart';
import 'src/echo_parameters.dart';

const CMD_INIT = 0x01;
const CMD_PROCESS = 0x02;
const CMD_SET_PARAM = 0x03;
const CMD_OPEN_UI = 0x04;
const CMD_CLOSE_UI = 0x05;
const CMD_GET_PARAM = 0x06;
const CMD_TERMINATE = 0xFF;

void main() async {
  final processor = EchoProcessor();
  final parameters = EchoParameters();
  Process? uiProcess;
  
  // CRITICAL: Set binary mode (only if stdin is a terminal)
  try {
    stdin.lineMode = false;
  } catch (e) {
    // Ignore error if stdin is not a terminal (e.g., when piped)
  }
  
  // Main event loop
  await for (final bytes in stdin) {
    if (bytes.isEmpty) continue;
    
    final buffer = ByteData.view(Uint8List.fromList(bytes).buffer);
    final command = buffer.getUint8(0);
    
    switch (command) {
      case CMD_INIT:
        final sampleRate = buffer.getFloat64(1, Endian.little);
        processor.initialize(sampleRate, 512);
        stdout.add([CMD_INIT]); // ACK
        await stdout.flush();
        break;
        
      case CMD_PROCESS:
        final numSamples = buffer.getInt32(1, Endian.little);
        // Read interleaved stereo
        final audioData = Float32List(numSamples * 2);
        for (int i = 0; i < numSamples * 2; i++) {
          audioData[i] = buffer.getFloat32(5 + i * 4, Endian.little);
        }
        
        // Split to L/R
        final inputL = List<double>.generate(numSamples, 
            (i) => audioData[i * 2].toDouble());
        final inputR = List<double>.generate(numSamples, 
            (i) => audioData[i * 2 + 1].toDouble());
        
        final outputL = List<double>.filled(numSamples, 0.0);
        final outputR = List<double>.filled(numSamples, 0.0);
        
        // PROCESS WITH YOUR DART CODE!
        processor.processStereo(inputL, inputR, outputL, outputR, parameters);
        
        // Send back interleaved
        final response = ByteData(1 + numSamples * 8);
        response.setUint8(0, CMD_PROCESS);
        for (int i = 0; i < numSamples; i++) {
          response.setFloat32(1 + i * 8, outputL[i], Endian.little);
          response.setFloat32(1 + i * 8 + 4, outputR[i], Endian.little);
        }
        
        stdout.add(response.buffer.asUint8List());
        await stdout.flush();
        break;
        
      case CMD_SET_PARAM:
        final paramId = buffer.getInt32(1, Endian.little);
        final value = buffer.getFloat64(5, Endian.little);
        parameters.setParameter(paramId, value);
        stdout.add([CMD_SET_PARAM]); // ACK
        await stdout.flush();
        break;
        
      case CMD_OPEN_UI:
        // Launch Flutter UI as separate process
        if (uiProcess == null) {
          try {
            // Build Flutter app path
            final currentDir = Directory.current.path;
            final flutterAppPath = '$currentDir/build/macos/Build/Products/Release/echo_ui.app';
            
            // Launch Flutter UI app on macOS
            uiProcess = await Process.start('open', [
              '-n', // Open new instance
              flutterAppPath,
              '--args',
              '--plugin-id=echo',
            ]);
            
            // Send success response with placeholder window handle
            // In real implementation, Flutter app would communicate back its window handle
            final response = ByteData(9);
            response.setUint8(0, CMD_OPEN_UI);
            response.setInt64(1, 0x12345678, Endian.little); // Placeholder window handle
            stdout.add(response.buffer.asUint8List());
            await stdout.flush();
            
            // Listen to UI process output
            uiProcess!.stdout.transform(utf8.decoder).listen((data) {
              // Handle UI -> Plugin communication
              stderr.writeln('UI: $data');
            });
            
            // Pass parameters to UI via shared memory or IPC
            // TODO: Implement proper parameter sharing
            
          } catch (e) {
            stderr.writeln('Failed to launch UI: $e');
            stdout.add([CMD_OPEN_UI, 0]); // Error response
            await stdout.flush();
          }
        } else {
          // UI already open, just bring to front
          // Send existing window handle
          final response = ByteData(9);
          response.setUint8(0, CMD_OPEN_UI);
          response.setInt64(1, 0x12345678, Endian.little);
          stdout.add(response.buffer.asUint8List());
          await stdout.flush();
        }
        break;
        
      case CMD_CLOSE_UI:
        // Close Flutter UI
        if (uiProcess != null) {
          uiProcess!.kill();
          uiProcess = null;
        }
        stdout.add([CMD_CLOSE_UI]); // ACK
        await stdout.flush();
        break;
        
      case CMD_GET_PARAM:
        final paramId = buffer.getInt32(1, Endian.little);
        final value = parameters.getParameter(paramId);
        final response = ByteData(9);
        response.setUint8(0, CMD_GET_PARAM);
        response.setFloat64(1, value, Endian.little);
        stdout.add(response.buffer.asUint8List());
        await stdout.flush();
        break;
        
      case CMD_TERMINATE:
        // Clean up UI if running
        if (uiProcess != null) {
          uiProcess!.kill();
        }
        exit(0);
    }
  }
}