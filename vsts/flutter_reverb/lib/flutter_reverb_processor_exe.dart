import 'dart:io';
import 'dart:typed_data';
import 'src/reverb_processor.dart';

const CMD_INIT = 0x01;
const CMD_PROCESS = 0x02;
const CMD_SET_PARAM = 0x03;
const CMD_TERMINATE = 0xFF;

void main() async {
  final processor = ReverbProcessor();
  
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
        
        // PROCESS WITH REVERB DART CODE!
        processor.processStereo(inputL, inputR, outputL, outputR);
        
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
        processor.setParameter(paramId, value);
        stdout.add([CMD_SET_PARAM]); // ACK
        await stdout.flush();
        break;
        
      case CMD_TERMINATE:
        exit(0);
    }
  }
}