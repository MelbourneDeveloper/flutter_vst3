import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/shared_memory_reader.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';

import 'shm_test_harness.dart';

void main() {
  test('reader routes four distinct channels and averages exactly', () {
    final memory = shmBlock();
    writeI32(memory, vst3OffsetNumSamples, 3);
    fillChannels(memory, samples: 3, scale: 10, base: 0.5);
    final reader = Vst3AudioBufferReader.fromAddress(memory.address)!;
    expect(reader.getInputL(), [0.5, 1.5, 2.5]);
    expect(reader.getInputR(), [10.5, 11.5, 12.5]);
    expect(reader.getOutputL(), [20.5, 21.5, 22.5]);
    expect(reader.getOutputR(), [30.5, 31.5, 32.5]);
    expect(reader.getLatestOutputSamples(), [25.5, 26.5, 27.5]);
    expect(reader.getLatestOutputSamples(maxCount: 2), [25.5, 26.5]);
    reader.getInputL()[1] = -7;
    expect(readF32(memory, vst3OffsetInputL, 1), -7);
  });
}
