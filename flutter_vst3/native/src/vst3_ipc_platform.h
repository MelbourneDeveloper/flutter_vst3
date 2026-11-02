// Copyright (c) 2025
// Operating system primitives used by Vst3IpcHost. Implemented separately for
// Win32 and POSIX in vst3_ipc_platform_win.cpp and vst3_ipc_platform_posix.cpp.

#pragma once

#include <cstdint>
#include <string>

#include "vst3_shared_memory.h"

namespace vst3_ipc {

long currentProcessId() noexcept;
const char* shmPrefix() noexcept;
const char* semReadyPrefix() noexcept;
const char* semDonePrefix() noexcept;

/// Creates a new semaphore at zero. Throws if the name is already in use.
void* semCreate(const std::string& name);
void semPost(void* sem) noexcept;
bool semTryWait(void* sem) noexcept;
bool semTimedWait(void* sem, double seconds) noexcept;
void semRelease(void* sem) noexcept;

/// Removes names from the system, so nothing outlives a host crash. The worker
/// must already have opened them.
void unlinkNames(const std::string& shm, const std::string& ready, const std::string& done) noexcept;

/// Creates a block of VST3_SHM_TOTAL_SIZE bytes, reusing a retired address if
/// there is one. On Windows a reused block keeps its old name, so name is an
/// in-out parameter.
Vst3SharedMemory* mapCreate(std::string& name, void*& handle);

/// Clears the magic word and keeps the address valid for in-process readers.
void mapRetire(Vst3SharedMemory* memory, void* handle, const std::string& name) noexcept;

/// Starts the worker with the block and semaphore names and this process's id.
intptr_t spawnWorker(const std::string& path, const std::string& shm, const std::string& ready,
                     const std::string& done);

/// Reports whether the child still runs. On POSIX this reaps a dead child.
bool childAlive(intptr_t child) noexcept;

/// Waits up to graceMs for the child to exit, then kills it, and releases it.
void childStop(intptr_t child, int graceMs) noexcept;

/// Releases what's still held for a child that childAlive reported dead.
void childReleaseDead(intptr_t child) noexcept;

int64_t childPid(intptr_t child) noexcept;

/// Absolute path of the module containing this code.
std::string modulePath();

}  // namespace vst3_ipc
