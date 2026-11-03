// Copyright (c) 2025
// Pool of retired memory blocks shared by the platform implementations.
//
// A retired block stays mapped so in-process readers can't fault on it. New
// instances reuse retired blocks, which bounds the cost to the peak instance
// count. The pool is deliberately never destroyed.

#pragma once

#include <mutex>
#include <string>
#include <vector>

#include "vst3_shared_memory.h"

namespace vst3_ipc {

struct RetiredMapping {
    Vst3SharedMemory* memory = nullptr;
    void* handle = nullptr;
    std::string name;
};

inline std::mutex& retiredMutex() {
    static auto* mutex = new std::mutex();
    return *mutex;
}

inline std::vector<RetiredMapping>& retiredMappings() {
    static auto* mappings = new std::vector<RetiredMapping>();
    return *mappings;
}

inline bool takeRetired(RetiredMapping& out) {
    std::lock_guard<std::mutex> lock(retiredMutex());
    auto& pool = retiredMappings();
    if (pool.empty()) return false;
    out = pool.back();
    pool.pop_back();
    return true;
}

inline void addRetired(RetiredMapping mapping) noexcept {
    std::lock_guard<std::mutex> lock(retiredMutex());
    retiredMappings().push_back(std::move(mapping));
}

}  // namespace vst3_ipc
