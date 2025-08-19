// Copyright (c) 2025
//
// Implementation of the C bridge for calling Dart reverb processor
// from VST3 plugin. This manages the callback functions and provides
// a C API that the VST3 processor can use.

#include "dart_reverb_bridge.h"
#include <cstring>
#include <mutex>

// Global callback storage and mutex for thread safety
static DartReverbCallbacks g_callbacks = {0};
static bool g_callbacks_registered = false;
static std::mutex g_mutex;

extern "C" {

int32_t dart_reverb_register_callbacks(const DartReverbCallbacks* callbacks) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!callbacks) return 0;
    
    // Copy all callback function pointers
    g_callbacks = *callbacks;
    g_callbacks_registered = true;
    
    return 1;
}

int32_t dart_reverb_initialize(double sample_rate, int32_t max_block_size) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.initialize_processor) {
        return 0;
    }
    
    g_callbacks.initialize_processor(sample_rate, max_block_size);
    return 1;
}

int32_t dart_reverb_process_stereo(const float* input_l, const float* input_r,
                                   float* output_l, float* output_r,
                                   int32_t num_samples) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.process_audio) {
        // If no Dart processor, pass through input to output
        if (input_l && output_l) {
            memcpy(output_l, input_l, num_samples * sizeof(float));
        }
        if (input_r && output_r) {
            memcpy(output_r, input_r, num_samples * sizeof(float));
        }
        return 0;
    }
    
    g_callbacks.process_audio(input_l, input_r, output_l, output_r, num_samples);
    return 1;
}

int32_t dart_reverb_set_parameter(int32_t param_id, double normalized_value) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.set_parameter) {
        return 0;
    }
    
    g_callbacks.set_parameter(param_id, normalized_value);
    return 1;
}

double dart_reverb_get_parameter(int32_t param_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.get_parameter) {
        return 0.0;
    }
    
    return g_callbacks.get_parameter(param_id);
}

int32_t dart_reverb_get_parameter_count(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.get_parameter_count) {
        return 0;
    }
    
    return g_callbacks.get_parameter_count();
}

int32_t dart_reverb_reset(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.reset) {
        return 0;
    }
    
    g_callbacks.reset();
    return 1;
}

int32_t dart_reverb_dispose(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_callbacks_registered || !g_callbacks.dispose) {
        return 0;
    }
    
    g_callbacks.dispose();
    
    // Clear callbacks
    memset(&g_callbacks, 0, sizeof(g_callbacks));
    g_callbacks_registered = false;
    
    return 1;
}

} // extern "C"