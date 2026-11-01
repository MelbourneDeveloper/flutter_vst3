// Copyright (c) 2025
// VST3 Shared Memory Audio Architecture
//
// Overview:
// Provides a zero-copy, real-time audio and parameter bridge between the
// C++ VST3 plugin wrapper (running inside the DAW audio thread) and the
// standalone Dart/Flutter audio processor process.
//
// Key Concepts:
// 1. Preallocated Shared Memory (POSIX shm_open + mmap):
//    A fixed memory region (68 KB) is shared between both processes. Audio
//    buffers and parameter queues are read and written directly in RAM without
//    data serialization or pipe buffering.
//
// 2. POSIX Named Semaphores (sem_ready & sem_done):
//    Coordinate lock-free synchronization between the DAW audio thread and
//    the Dart DSP process:
//    - C++ sets input audio, command, and calls sem_post(sem_ready).
//    - Dart wakes up via sem_wait(sem_ready), processes samples in-place,
//      and signals back via sem_post(sem_done).
//    - C++ waits on sem_done (with a safety timeout) and copies processed audio.
//
// 3. Lock-free FIFO Parameter Queues:
//    Host parameter automation (DAW -> Dart) and UI changes (Dart UI -> DAW)
//    are passed via circular ring buffers indexed by write/read counters.

#pragma once

#include <stdint.h>

/// Magic identifier ('VST3') validating memory layout compatibility.
#define VST3_SHM_MAGIC 0x56535433

/// Protocol version number.
#define VST3_SHM_VERSION 1

/// Maximum number of audio samples supported per processing block (e.g. 4096 samples).
#define VST3_SHM_MAX_SAMPLES 4096

/// Capacity of the circular parameter ring buffers.
#define VST3_SHM_PARAM_QUEUE_SIZE 64

// Commands sent from C++ host wrapper to Dart processor via Vst3SharedMemory::command
#define VST3_CMD_IDLE 0        // Standby / no-op
#define VST3_CMD_PROCESS 1     // Process the current audio buffer in numSamples
#define VST3_CMD_TERMINATE 2   // Shut down the Dart processor event loop

// Fixed memory byte offsets ensuring exact binary alignment across C++ and Dart FFI
#define VST3_SHM_OFFSET_MAGIC 0
#define VST3_SHM_OFFSET_VERSION 4
#define VST3_SHM_OFFSET_SAMPLE_RATE 8
#define VST3_SHM_OFFSET_MAX_BLOCK_SIZE 16
#define VST3_SHM_OFFSET_COMMAND 20
#define VST3_SHM_OFFSET_NUM_SAMPLES 24
#define VST3_SHM_OFFSET_HOST_PARAM_WRITE 28
#define VST3_SHM_OFFSET_HOST_PARAM_READ 32
#define VST3_SHM_OFFSET_HOST_PARAMS 36
#define VST3_SHM_OFFSET_UI_PARAM_WRITE 1060
#define VST3_SHM_OFFSET_UI_PARAM_READ 1064
#define VST3_SHM_OFFSET_UI_PARAMS 1068
#define VST3_SHM_OFFSET_INPUT_L 4096
#define VST3_SHM_OFFSET_INPUT_R 20480
#define VST3_SHM_OFFSET_OUTPUT_L 36864
#define VST3_SHM_OFFSET_OUTPUT_R 53248
#define VST3_SHM_TOTAL_SIZE 69632

#pragma pack(push, 1)

/// Represents a single parameter change event within the lock-free ring buffer.
struct Vst3ParamEvent {
    int32_t paramId;  // Target parameter identifier
    int32_t padding;  // Alignment padding
    double value;     // Normalized parameter value (0.0 to 1.0)
};

/// Main shared memory layout mapped between C++ and Dart processes.
/// Exactly 69,632 bytes (17 x 4096-byte pages) with audio buffers page-aligned at 4096.
struct Vst3SharedMemory {
    // Header & control flags
    uint32_t magic;         // Set to VST3_SHM_MAGIC (0x56535433)
    uint32_t version;       // Protocol version (VST3_SHM_VERSION)
    double sampleRate;      // Host sample rate in Hz (e.g. 44100.0, 48000.0)
    uint32_t maxBlockSize;  // Host maximum buffer block size
    uint32_t command;       // Active command: VST3_CMD_PROCESS or VST3_CMD_TERMINATE
    int32_t numSamples;     // Number of valid samples in the current processing block
    
    // Lock-free Parameter queue: DAW host automation -> Dart DSP processor
    uint32_t hostParamWriteIndex;
    uint32_t hostParamReadIndex;
    Vst3ParamEvent hostParams[VST3_SHM_PARAM_QUEUE_SIZE];
    
    // Lock-free Parameter queue: Dart UI -> DAW host controller
    uint32_t uiParamWriteIndex;
    uint32_t uiParamReadIndex;
    Vst3ParamEvent uiParams[VST3_SHM_PARAM_QUEUE_SIZE];
    
    uint8_t reserved[2004]; // Padding to align audio buffers to 4096 bytes
    
    // Preallocated Audio Buffers (page-aligned at offset 4096 for optimal SIMD throughput)
    float inputL[VST3_SHM_MAX_SAMPLES];   // Left channel input from DAW
    float inputR[VST3_SHM_MAX_SAMPLES];   // Right channel input from DAW
    float outputL[VST3_SHM_MAX_SAMPLES];  // Left channel output back to DAW
    float outputR[VST3_SHM_MAX_SAMPLES];  // Right channel output back to DAW
};
#pragma pack(pop)

#ifdef __cplusplus
extern "C" {
#endif

/// Registers the active shared memory mapping for UI buffer readers.
void vst3_set_active_shm(const char* name, struct Vst3SharedMemory* shm);

/// Returns the name of the currently active POSIX/Win32 shared memory segment.
const char* vst3_get_active_shm_name();

/// Returns a direct pointer to the active Vst3SharedMemory structure in this process.
struct Vst3SharedMemory* vst3_get_active_shm_ptr();

#ifdef __cplusplus
}
#endif

