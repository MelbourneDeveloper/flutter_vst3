// Copyright (c) 2025
// VST3 shared memory layout
//
// One fixed block of memory is shared between the plugin (inside the host) and
// its Dart worker process. Audio is copied in and out of it once per block.
//
// Ownership of the block passes between the processes with two named
// semaphores, so no field needs to be atomic:
// - The plugin owns the block until it posts sem_ready.
// - The worker owns the block from sem_ready until it posts sem_done.
// If the worker runs late, the plugin leaves the block alone until the late
// sem_done arrives.
//
// flutter_vst3/lib/src/vst3_shm_layout.dart mirrors these constants, and
// flutter_vst3/test/vst3_shm_layout_test.dart fails if the two differ.

#pragma once

#include <stddef.h>
#include <stdint.h>

/// Magic identifier ('VST3') validating memory layout compatibility.
#define VST3_SHM_MAGIC 0x56535433

/// Protocol version number.
#define VST3_SHM_VERSION 2

/// Maximum number of audio samples supported per processing block (e.g. 4096 samples).
#define VST3_SHM_MAX_SAMPLES 4096

/// Capacity of the circular parameter ring buffers.
#define VST3_SHM_PARAM_QUEUE_SIZE 64

// Commands sent from C++ host wrapper to Dart processor via Vst3SharedMemory::command
#define VST3_CMD_IDLE 0        // Standby / no-op
#define VST3_CMD_PROCESS 1     // Process the current audio buffer in numSamples
#define VST3_CMD_TERMINATE 2   // Shut down the Dart processor event loop
#define VST3_CMD_CONFIGURE 3   // Reinitialize the DSP from sampleRate and maxBlockSize
#define VST3_CMD_RESET 4       // Clear DSP state such as delay tails

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

/// Represents a single parameter change event within a ring buffer.
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
    
    // Parameter queue: DAW host automation -> Dart DSP processor
    uint32_t hostParamWriteIndex;
    uint32_t hostParamReadIndex;
    Vst3ParamEvent hostParams[VST3_SHM_PARAM_QUEUE_SIZE];
    
    // Parameter queue: Dart UI -> DAW host controller
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
static_assert(offsetof(Vst3SharedMemory, version) == VST3_SHM_OFFSET_VERSION, "layout");
static_assert(offsetof(Vst3SharedMemory, sampleRate) == VST3_SHM_OFFSET_SAMPLE_RATE, "layout");
static_assert(offsetof(Vst3SharedMemory, maxBlockSize) == VST3_SHM_OFFSET_MAX_BLOCK_SIZE, "layout");
static_assert(offsetof(Vst3SharedMemory, command) == VST3_SHM_OFFSET_COMMAND, "layout");
static_assert(offsetof(Vst3SharedMemory, numSamples) == VST3_SHM_OFFSET_NUM_SAMPLES, "layout");
static_assert(offsetof(Vst3SharedMemory, hostParamWriteIndex) == VST3_SHM_OFFSET_HOST_PARAM_WRITE, "layout");
static_assert(offsetof(Vst3SharedMemory, hostParamReadIndex) == VST3_SHM_OFFSET_HOST_PARAM_READ, "layout");
static_assert(offsetof(Vst3SharedMemory, hostParams) == VST3_SHM_OFFSET_HOST_PARAMS, "layout");
static_assert(offsetof(Vst3SharedMemory, uiParamWriteIndex) == VST3_SHM_OFFSET_UI_PARAM_WRITE, "layout");
static_assert(offsetof(Vst3SharedMemory, uiParamReadIndex) == VST3_SHM_OFFSET_UI_PARAM_READ, "layout");
static_assert(offsetof(Vst3SharedMemory, uiParams) == VST3_SHM_OFFSET_UI_PARAMS, "layout");
static_assert(offsetof(Vst3SharedMemory, inputL) == VST3_SHM_OFFSET_INPUT_L, "layout");
static_assert(offsetof(Vst3SharedMemory, inputR) == VST3_SHM_OFFSET_INPUT_R, "layout");
static_assert(offsetof(Vst3SharedMemory, outputL) == VST3_SHM_OFFSET_OUTPUT_L, "layout");
static_assert(offsetof(Vst3SharedMemory, outputR) == VST3_SHM_OFFSET_OUTPUT_R, "layout");
static_assert(sizeof(Vst3ParamEvent) == 16, "layout");
static_assert(sizeof(Vst3SharedMemory) == VST3_SHM_TOTAL_SIZE, "layout");
#endif
