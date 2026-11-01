import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/vst3_shm_layout.dart';

void main() {
  test('every native protocol define matches Dart', () {
    final header =
        File('native/include/vst3_shared_memory.h').readAsStringSync();
    final expected = <String, int>{
      'VST3_SHM_MAGIC': vst3ShmMagic,
      'VST3_SHM_VERSION': vst3ShmVersion,
      'VST3_SHM_MAX_SAMPLES': vst3ShmMaxSamples,
      'VST3_SHM_PARAM_QUEUE_SIZE': vst3ShmParamQueueSize,
      'VST3_CMD_IDLE': 0,
      'VST3_CMD_PROCESS': vst3CmdProcess,
      'VST3_CMD_TERMINATE': vst3CmdTerminate,
      'VST3_CMD_CONFIGURE': vst3CmdConfigure,
      'VST3_CMD_RESET': vst3CmdReset,
      'VST3_SHM_OFFSET_MAGIC': vst3OffsetMagic,
      'VST3_SHM_OFFSET_VERSION': vst3OffsetVersion,
      'VST3_SHM_OFFSET_SAMPLE_RATE': vst3OffsetSampleRate,
      'VST3_SHM_OFFSET_MAX_BLOCK_SIZE': vst3OffsetMaxBlockSize,
      'VST3_SHM_OFFSET_COMMAND': vst3OffsetCommand,
      'VST3_SHM_OFFSET_NUM_SAMPLES': vst3OffsetNumSamples,
      'VST3_SHM_OFFSET_HOST_PARAM_WRITE': vst3OffsetHostParamWrite,
      'VST3_SHM_OFFSET_HOST_PARAM_READ': vst3OffsetHostParamRead,
      'VST3_SHM_OFFSET_HOST_PARAMS': vst3OffsetHostParams,
      'VST3_SHM_OFFSET_UI_PARAM_WRITE': 1060,
      'VST3_SHM_OFFSET_UI_PARAM_READ': 1064,
      'VST3_SHM_OFFSET_UI_PARAMS': 1068,
      'VST3_SHM_OFFSET_INPUT_L': vst3OffsetInputL,
      'VST3_SHM_OFFSET_INPUT_R': vst3OffsetInputR,
      'VST3_SHM_OFFSET_OUTPUT_L': vst3OffsetOutputL,
      'VST3_SHM_OFFSET_OUTPUT_R': vst3OffsetOutputR,
      'VST3_SHM_TOTAL_SIZE': vst3ShmTotalSize,
    };
    final matches = RegExp(r'^#define (VST3_\w+) (0x[0-9a-fA-F]+|[0-9]+)\b',
            multiLine: true)
        .allMatches(header);
    expect(matches.length, 26);
    expect(expected.length, 26);
    for (final match in matches) {
      expect(expected, contains(match[1]));
      expect(int.parse(match[2]!), expected[match[1]], reason: match[1]);
    }
  });
}
