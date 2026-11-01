/// Shared memory layout mirrored from native/include/vst3_shared_memory.h.
///
/// test/vst3_shm_layout_test.dart fails if these values differ from the header.
library;

/// Magic word identifying a live block ('VST3').
const int vst3ShmMagic = 0x56535433;

/// Protocol version. The worker refuses a block with any other version.
const int vst3ShmVersion = 2;

/// Maximum samples in one block.
const int vst3ShmMaxSamples = 4096;

/// Capacity of the parameter ring.
const int vst3ShmParamQueueSize = 64;

/// Size in bytes of one parameter event.
const int vst3ShmParamEventSize = 16;

/// Host command: process the audio block.
const int vst3CmdProcess = 1;

/// Host command: exit the event loop.
const int vst3CmdTerminate = 2;

/// Host command: reinitialize the DSP from the sample rate and block size.
const int vst3CmdConfigure = 3;

/// Host command: clear DSP state.
const int vst3CmdReset = 4;

/// Byte offset of the magic word.
const int vst3OffsetMagic = 0;

/// Byte offset of the protocol version.
const int vst3OffsetVersion = 4;

/// Byte offset of the sample rate.
const int vst3OffsetSampleRate = 8;

/// Byte offset of the maximum block size.
const int vst3OffsetMaxBlockSize = 16;

/// Byte offset of the command.
const int vst3OffsetCommand = 20;

/// Byte offset of the sample count.
const int vst3OffsetNumSamples = 24;

/// Byte offset of the parameter ring write index.
const int vst3OffsetHostParamWrite = 28;

/// Byte offset of the parameter ring read index.
const int vst3OffsetHostParamRead = 32;

/// Byte offset of the parameter ring.
const int vst3OffsetHostParams = 36;

/// Byte offset of the left input.
const int vst3OffsetInputL = 4096;

/// Byte offset of the right input.
const int vst3OffsetInputR = 20480;

/// Byte offset of the left output.
const int vst3OffsetOutputL = 36864;

/// Byte offset of the right output.
const int vst3OffsetOutputR = 53248;

/// Total size of the block in bytes.
const int vst3ShmTotalSize = 69632;
