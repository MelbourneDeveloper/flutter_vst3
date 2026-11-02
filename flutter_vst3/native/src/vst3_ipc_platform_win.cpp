// Copyright (c) 2025
// Win32 implementation of vst3_ipc_platform.h.

#ifdef _WIN32

#include "vst3_ipc_platform.h"

#include <windows.h>

#include <stdexcept>
#include <vector>

#include "vst3_ipc_retired.h"

namespace vst3_ipc {
namespace {

void moduleAnchor() {}

Vst3SharedMemory* mapNew(const std::string& name, void*& handle) {
    HANDLE mapping = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                        VST3_SHM_TOTAL_SIZE, name.c_str());
    if (!mapping) throw std::runtime_error("CreateFileMapping failed: " + name);
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(mapping);
        throw std::runtime_error("Shared memory already exists: " + name);
    }
    void* view = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, VST3_SHM_TOTAL_SIZE);
    if (!view) {
        CloseHandle(mapping);
        throw std::runtime_error("MapViewOfFile failed: " + name);
    }
    handle = mapping;
    return static_cast<Vst3SharedMemory*>(view);
}

}  // namespace

long currentProcessId() noexcept { return static_cast<long>(GetCurrentProcessId()); }
const char* shmPrefix() noexcept { return "Local\\v3s"; }
const char* semReadyPrefix() noexcept { return "Local\\v3r"; }
const char* semDonePrefix() noexcept { return "Local\\v3d"; }

void* semCreate(const std::string& name) {
    HANDLE handle = CreateSemaphoreA(nullptr, 0, 1000, name.c_str());
    if (!handle) throw std::runtime_error("CreateSemaphore failed: " + name);
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(handle);
        throw std::runtime_error("Semaphore already exists: " + name);
    }
    return handle;
}

void semPost(void* sem) noexcept { ReleaseSemaphore(sem, 1, nullptr); }
bool semTryWait(void* sem) noexcept { return WaitForSingleObject(sem, 0) == WAIT_OBJECT_0; }

bool semTimedWait(void* sem, double seconds) noexcept {
    const DWORD ms = static_cast<DWORD>(seconds * 1000.0 + 0.999);
    return WaitForSingleObject(sem, ms) == WAIT_OBJECT_0;
}

void semRelease(void* sem) noexcept { CloseHandle(sem); }

// Win32 kernel objects disappear with their last handle, so no unlink step.
void unlinkNames(const std::string&, const std::string&, const std::string&) noexcept {}

Vst3SharedMemory* mapCreate(std::string& name, void*& handle) {
    RetiredMapping retired;
    if (!takeRetired(retired)) return mapNew(name, handle);
    name = retired.name;
    handle = retired.handle;
    return retired.memory;
}

// UnmapViewOfFile would let an in-process reader fault, so the view stays.
void mapRetire(Vst3SharedMemory* memory, void* handle, const std::string& name) noexcept {
    memory->magic = 0;
    RetiredMapping retired;
    retired.memory = memory;
    retired.handle = handle;
    retired.name = name;
    addRetired(std::move(retired));
}

intptr_t spawnWorker(const std::string& path, const std::string& shm, const std::string& ready,
                     const std::string& done) {
    const std::string cmd = "\"" + path + "\" \"" + shm + "\" \"" + ready + "\" \"" + done + "\" " +
                            std::to_string(currentProcessId());
    std::vector<char> buffer(cmd.begin(), cmd.end());
    buffer.push_back('\0');
    STARTUPINFOA startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION info{};
    if (!CreateProcessA(nullptr, buffer.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                        nullptr, &startup, &info)) {
        throw std::runtime_error("Failed to start Dart worker: " + path);
    }
    CloseHandle(info.hThread);
    return reinterpret_cast<intptr_t>(info.hProcess);
}

bool childAlive(intptr_t child) noexcept {
    return child != 0 && WaitForSingleObject(reinterpret_cast<HANDLE>(child), 0) == WAIT_TIMEOUT;
}

void childStop(intptr_t child, int graceMs) noexcept {
    HANDLE handle = reinterpret_cast<HANDLE>(child);
    if (WaitForSingleObject(handle, static_cast<DWORD>(graceMs)) != WAIT_OBJECT_0) TerminateProcess(handle, 1);
    WaitForSingleObject(handle, INFINITE);
    CloseHandle(handle);
}

void childReleaseDead(intptr_t child) noexcept { CloseHandle(reinterpret_cast<HANDLE>(child)); }

int64_t childPid(intptr_t child) noexcept {
    return static_cast<int64_t>(GetProcessId(reinterpret_cast<HANDLE>(child)));
}

std::string modulePath() {
    HMODULE module = nullptr;
    char path[MAX_PATH];
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCSTR>(&moduleAnchor), &module) ||
        GetModuleFileNameA(module, path, sizeof(path)) == 0) {
        throw std::runtime_error("Failed to locate the VST3 module");
    }
    return path;
}

}  // namespace vst3_ipc

#endif
