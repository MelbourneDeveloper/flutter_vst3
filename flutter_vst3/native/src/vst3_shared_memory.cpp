// Copyright (c) 2025
// Implementation of active shared memory tracking for VST3 plugins.

#include "vst3_shared_memory.h"
#include <string>

static std::string s_activeShmName;
static Vst3SharedMemory* s_activeShmPtr = nullptr;

extern "C" {

void vst3_set_active_shm(const char* name, Vst3SharedMemory* shm) {
    s_activeShmName = name ? name : "";
    s_activeShmPtr = shm;
}

const char* vst3_get_active_shm_name() {
    return s_activeShmName.empty() ? nullptr : s_activeShmName.c_str();
}

Vst3SharedMemory* vst3_get_active_shm_ptr() {
    return s_activeShmPtr;
}

}
