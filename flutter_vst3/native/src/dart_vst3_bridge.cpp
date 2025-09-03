// Copyright (c) 2025
//
// Implementation of the generic C bridge for calling Dart VST3 processors
// from C++. This manages callback functions per plugin instance and provides
// a universal C API that any VST3 processor can use.

#include "dart_vst3_bridge.h"
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <string>
#include <stdexcept>
#include <cstdio>
#include <cstdlib>

// Per-instance data structure
struct DartVST3Instance {
    std::string plugin_id;
    DartVST3Callbacks callbacks;
    bool callbacks_registered;
    std::mutex mutex;
    
    DartVST3Instance(const std::string& id) 
        : plugin_id(id), callbacks{0}, callbacks_registered(false) {}
};

// Global instance registry
static std::unordered_map<DartVST3Instance*, std::unique_ptr<DartVST3Instance>> g_instances;
static std::mutex g_instances_mutex;

extern "C" {

DartVST3Instance* dart_vst3_create_instance(const char* plugin_id) {
    std::lock_guard<std::mutex> lock(g_instances_mutex);
    
    if (!plugin_id) return nullptr;
    
    auto instance = std::make_unique<DartVST3Instance>(plugin_id);
    auto* raw_ptr = instance.get();
    g_instances[raw_ptr] = std::move(instance);
    
    return raw_ptr;
}

int32_t dart_vst3_destroy_instance(DartVST3Instance* instance) {
    std::lock_guard<std::mutex> lock(g_instances_mutex);
    
    if (!instance) return 0;
    
    auto it = g_instances.find(instance);
    if (it != g_instances.end()) {
        g_instances.erase(it);
        return 1;
    }
    
    return 0;
}

int32_t dart_vst3_register_callbacks(DartVST3Instance* instance, 
                                     const DartVST3Callbacks* callbacks) {
    if (!instance || !callbacks) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    // Copy all callback function pointers
    instance->callbacks = *callbacks;
    instance->callbacks_registered = true;
    
    return 1;
}

int32_t dart_vst3_initialize(DartVST3Instance* instance, 
                            double sample_rate, int32_t max_block_size) {
    if (!instance) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.initialize_processor) {
        return 0;
    }
    
    instance->callbacks.initialize_processor(sample_rate, max_block_size);
    return 1;
}

int32_t dart_vst3_process_stereo(DartVST3Instance* instance,
                                const float* input_l, const float* input_r,
                                float* output_l, float* output_r,
                                int32_t num_samples) {
    if (!instance) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.process_audio) {
        // NO FALLBACKS! FAIL HARD! CRASH THE ENTIRE PLUGIN!
        fprintf(stderr, "CRITICAL VST3 BRIDGE FAILURE: No Dart callbacks registered! Plugin ID: %s\n", instance->plugin_id.c_str());
        fprintf(stderr, "CALLBACKS_REGISTERED: %d\n", instance->callbacks_registered);
        fprintf(stderr, "PROCESS_AUDIO CALLBACK: %p\n", (void*)instance->callbacks.process_audio);
        fflush(stderr);
        abort(); // KILL THE PLUGIN HARD!
    }
    
    instance->callbacks.process_audio(input_l, input_r, output_l, output_r, num_samples);
    return 1;
}

int32_t dart_vst3_set_parameter(DartVST3Instance* instance,
                                int32_t param_id, double normalized_value) {
    if (!instance) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.set_parameter) {
        return 0;
    }
    
    instance->callbacks.set_parameter(param_id, normalized_value);
    return 1;
}

double dart_vst3_get_parameter(DartVST3Instance* instance, int32_t param_id) {
    if (!instance) return 0.0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.get_parameter) {
        return 0.0;
    }
    
    return instance->callbacks.get_parameter(param_id);
}

int32_t dart_vst3_get_parameter_count(DartVST3Instance* instance) {
    if (!instance) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.get_parameter_count) {
        return 0;
    }
    
    return instance->callbacks.get_parameter_count();
}

int32_t dart_vst3_reset(DartVST3Instance* instance) {
    if (!instance) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.reset) {
        return 0;
    }
    
    instance->callbacks.reset();
    return 1;
}

int32_t dart_vst3_dispose(DartVST3Instance* instance) {
    if (!instance) return 0;
    
    std::lock_guard<std::mutex> lock(instance->mutex);
    
    if (!instance->callbacks_registered || !instance->callbacks.dispose) {
        return 0;
    }
    
    instance->callbacks.dispose();
    return 1;
}

}  // extern "C"