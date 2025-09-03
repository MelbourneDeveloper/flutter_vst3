// Copyright (c) 2025
//
// Generic C bridge for calling Dart VST3 processors from C++
// This provides a universal interface between VST3 C++ code and
// pure Dart implementations via FFI callbacks.

#pragma once
#include <stdint.h>

#ifdef _WIN32
#  ifdef DART_VST_HOST_EXPORTS
#    define DART_VST3_API __declspec(dllexport)
#  else
#    define DART_VST3_API __declspec(dllimport)
#  endif
#else
#  define DART_VST3_API __attribute__((visibility("default")))
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
} DartVST3Callbacks;

// Per-plugin instance management
typedef struct DartVST3Instance DartVST3Instance;

// Create a new plugin instance
DART_VST3_API DartVST3Instance* dart_vst3_create_instance(const char* plugin_id);

// Destroy a plugin instance
DART_VST3_API int32_t dart_vst3_destroy_instance(DartVST3Instance* instance);

// Register Dart callback functions for a specific plugin instance
DART_VST3_API int32_t dart_vst3_register_callbacks(DartVST3Instance* instance, 
                                                   const DartVST3Callbacks* callbacks);

// Initialize the Dart processor
DART_VST3_API int32_t dart_vst3_initialize(DartVST3Instance* instance, 
                                           double sample_rate, int32_t max_block_size);

// Process stereo audio through Dart processor
DART_VST3_API int32_t dart_vst3_process_stereo(DartVST3Instance* instance,
                                               const float* input_l, const float* input_r,
                                               float* output_l, float* output_r,
                                               int32_t num_samples);

// Set/get parameter values
DART_VST3_API int32_t dart_vst3_set_parameter(DartVST3Instance* instance,
                                              int32_t param_id, double normalized_value);
DART_VST3_API double dart_vst3_get_parameter(DartVST3Instance* instance, int32_t param_id);
DART_VST3_API int32_t dart_vst3_get_parameter_count(DartVST3Instance* instance);

// Reset processor state
DART_VST3_API int32_t dart_vst3_reset(DartVST3Instance* instance);

// Dispose resources
DART_VST3_API int32_t dart_vst3_dispose(DartVST3Instance* instance);

#ifdef __cplusplus
}
#endif