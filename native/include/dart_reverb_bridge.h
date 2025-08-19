// Copyright (c) 2025
//
// C bridge for calling Dart reverb processor from VST3 plugin
// This provides the interface between the VST3 C++ code and the
// pure Dart reverb implementation via FFI callbacks.

#pragma once
#include <stdint.h>

#ifdef _WIN32
#  ifdef DART_VST_HOST_EXPORTS
#    define DART_REVERB_API __declspec(dllexport)
#  else
#    define DART_REVERB_API __declspec(dllimport)
#  endif
#else
#  define DART_REVERB_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Function pointer types for Dart callbacks
typedef void (*DartInitializeProcessorFn)(double sample_rate, int32_t max_block_size);
typedef void (*DartProcessAudioFn)(const float* input_l, const float* input_r,
                                  float* output_l, float* output_r,
                                  int32_t num_samples);
typedef void (*DartSetParameterFn)(int32_t param_id, double normalized_value);
typedef double (*DartGetParameterFn)(int32_t param_id);
typedef int32_t (*DartGetParameterCountFn)(void);
typedef void (*DartResetFn)(void);
typedef void (*DartDisposeFn)(void);

// Structure holding all Dart callback functions
typedef struct {
    DartInitializeProcessorFn initialize_processor;
    DartProcessAudioFn process_audio;
    DartSetParameterFn set_parameter;
    DartGetParameterFn get_parameter;
    DartGetParameterCountFn get_parameter_count;
    DartResetFn reset;
    DartDisposeFn dispose;
} DartReverbCallbacks;

// Register Dart callback functions with the C++ layer
// Must be called before any other dart_reverb functions
DART_REVERB_API int32_t dart_reverb_register_callbacks(const DartReverbCallbacks* callbacks);

// Initialize the Dart reverb processor
DART_REVERB_API int32_t dart_reverb_initialize(double sample_rate, int32_t max_block_size);

// Process stereo audio through Dart reverb
DART_REVERB_API int32_t dart_reverb_process_stereo(const float* input_l, const float* input_r,
                                                   float* output_l, float* output_r,
                                                   int32_t num_samples);

// Set/get parameter values
DART_REVERB_API int32_t dart_reverb_set_parameter(int32_t param_id, double normalized_value);
DART_REVERB_API double dart_reverb_get_parameter(int32_t param_id);
DART_REVERB_API int32_t dart_reverb_get_parameter_count(void);

// Reset processor state
DART_REVERB_API int32_t dart_reverb_reset(void);

// Dispose resources
DART_REVERB_API int32_t dart_reverb_dispose(void);

// Parameter IDs matching Dart ReverbParameters
#define DART_REVERB_PARAM_ROOM_SIZE   0
#define DART_REVERB_PARAM_DAMPING     1
#define DART_REVERB_PARAM_WET_LEVEL   2
#define DART_REVERB_PARAM_DRY_LEVEL   3
#define DART_REVERB_PARAM_COUNT       4

#ifdef __cplusplus
}
#endif