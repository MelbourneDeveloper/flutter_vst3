// Copyright (c) 2025
// POSIX implementation of vst3_ipc_platform.h.

#ifndef _WIN32

#include "vst3_ipc_platform.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <semaphore.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <chrono>
#include <stdexcept>
#include <thread>

#if defined(__linux__)
#include <sys/syscall.h>
#endif

#include "vst3_ipc_retired.h"

namespace vst3_ipc {
namespace {

void moduleAnchor() {}

/// Closes everything the host left open, such as audio devices and sockets.
/// Runs between fork and exec, so only async-signal-safe calls are allowed.
void closeInheritedDescriptors() noexcept {
#if defined(__linux__) && defined(SYS_close_range)
    syscall(SYS_close_range, 3U, ~0U, 0U);
#else
    const int limit = getdtablesize();
    for (int fd = 3; fd < limit; ++fd) close(fd);
#endif
}

}  // namespace

long currentProcessId() noexcept { return static_cast<long>(getpid()); }
const char* shmPrefix() noexcept { return "/v3s"; }
const char* semReadyPrefix() noexcept { return "/v3r"; }
const char* semDonePrefix() noexcept { return "/v3d"; }

void* semCreate(const std::string& name) {
    sem_t* sem = sem_open(name.c_str(), O_CREAT | O_EXCL, 0600, 0);
    if (sem == SEM_FAILED) throw std::runtime_error("sem_open failed: " + name);
    return sem;
}

void semPost(void* sem) noexcept { sem_post(static_cast<sem_t*>(sem)); }
bool semTryWait(void* sem) noexcept { return sem_trywait(static_cast<sem_t*>(sem)) == 0; }

#if defined(__APPLE__)
// macOS has no sem_timedwait, so this is the one place that has to poll.
bool semTimedWait(void* sem, double seconds) noexcept {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::duration<double>(seconds);
    do {
        if (semTryWait(sem)) return true;
        std::this_thread::sleep_for(std::chrono::microseconds(50));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}
#else
bool semTimedWait(void* sem, double seconds) noexcept {
    timespec deadline{};
    clock_gettime(CLOCK_REALTIME, &deadline);
    const auto wholeSeconds = static_cast<time_t>(seconds);
    deadline.tv_sec += wholeSeconds;
    deadline.tv_nsec += static_cast<long>((seconds - static_cast<double>(wholeSeconds)) * 1e9);
    deadline.tv_sec += deadline.tv_nsec / 1000000000L;
    deadline.tv_nsec %= 1000000000L;
    int result = 0;
    do {
        result = sem_timedwait(static_cast<sem_t*>(sem), &deadline);
    } while (result != 0 && errno == EINTR);
    return result == 0;
}
#endif

void semRelease(void* sem) noexcept { sem_close(static_cast<sem_t*>(sem)); }

void unlinkNames(const std::string& shm, const std::string& ready, const std::string& done) noexcept {
    shm_unlink(shm.c_str());
    sem_unlink(ready.c_str());
    sem_unlink(done.c_str());
}

Vst3SharedMemory* mapCreate(std::string& name, void*& handle) {
    const int fd = shm_open(name.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) throw std::runtime_error("shm_open failed: " + name);
    if (ftruncate(fd, VST3_SHM_TOTAL_SIZE) != 0) {
        close(fd);
        shm_unlink(name.c_str());
        throw std::runtime_error("ftruncate failed: " + name);
    }
    RetiredMapping retired;
    const bool reuse = takeRetired(retired);
    void* address = mmap(reuse ? retired.memory : nullptr, VST3_SHM_TOTAL_SIZE, PROT_READ | PROT_WRITE,
                         MAP_SHARED | (reuse ? MAP_FIXED : 0), fd, 0);
    close(fd);
    if (address == MAP_FAILED) {
        shm_unlink(name.c_str());
        throw std::runtime_error("mmap failed: " + name);
    }
    handle = nullptr;
    return static_cast<Vst3SharedMemory*>(address);
}

void mapRetire(Vst3SharedMemory* memory, void*, const std::string&) noexcept {
    memory->magic = 0;
    mmap(memory, VST3_SHM_TOTAL_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    RetiredMapping retired;
    retired.memory = memory;
    addRetired(std::move(retired));
}

intptr_t spawnWorker(const std::string& path, const std::string& shm, const std::string& ready,
                     const std::string& done) {
    const std::string hostPid = std::to_string(currentProcessId());
    const pid_t child = fork();
    if (child < 0) throw std::runtime_error("fork failed for Dart worker: " + path);
    if (child == 0) {
        closeInheritedDescriptors();
        execl(path.c_str(), path.c_str(), shm.c_str(), ready.c_str(), done.c_str(), hostPid.c_str(),
              static_cast<char*>(nullptr));
        _exit(127);
    }
    return static_cast<intptr_t>(child);
}

bool childAlive(intptr_t child) noexcept {
    int status = 0;
    return child != 0 && waitpid(static_cast<pid_t>(child), &status, WNOHANG) == 0;
}

void childStop(intptr_t child, int graceMs) noexcept {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(graceMs);
    while (std::chrono::steady_clock::now() < deadline) {
        if (!childAlive(child)) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    kill(static_cast<pid_t>(child), SIGKILL);
    int status = 0;
    waitpid(static_cast<pid_t>(child), &status, 0);
}

int64_t childPid(intptr_t child) noexcept { return static_cast<int64_t>(child); }

std::string modulePath() {
    Dl_info info{};
    if (dladdr(reinterpret_cast<void*>(&moduleAnchor), &info) == 0 || !info.dli_fname) {
        throw std::runtime_error("Failed to locate the VST3 module");
    }
    return info.dli_fname;
}

}  // namespace vst3_ipc

#endif
