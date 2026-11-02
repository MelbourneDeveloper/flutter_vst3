// Direct platform regression tests; include host implementation to test private naming.
#include "vst3_ipc_host.cpp"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
#endif
using namespace vst3_ipc;
void check(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
void namesTest() {
    const auto a = reinterpret_cast<void*>(uintptr_t{0x12345678});
    const auto b = reinterpret_cast<void*>(uintptr_t{0x12355678});
    const auto first = uniqueName(shmPrefix(), a);
    const auto second = uniqueName(shmPrefix(), b);
    check(first != second, "host names collide");
    check(first.find("_12345678_") != std::string::npos, "first owner truncated");
    check(second.find("_12355678_") != std::string::npos, "second owner truncated");
    std::cout << "PASS full owner names with identical low 16 bits\n";
}
void mapCollision(std::string name, Vst3SharedMemory* memory) {
    memory->magic = 0x1234abcd;
    void* duplicateHandle = nullptr;
    bool threw = false;
    try { mapCreate(name, duplicateHandle); }
    catch (const std::runtime_error&) { threw = true; }
    check(memory->magic == 0x1234abcd, "mapping sentinel changed");
    check(threw, "duplicate mapping did not throw");
}
void semaphoreCollision(const std::string& name, void* sem) {
    semPost(sem);
    bool threw = false;
    try { semCreate(name); }
    catch (const std::runtime_error&) { threw = true; }
    check(semTryWait(sem), "semaphore sentinel lost");
    check(!semTryWait(sem), "semaphore count not exactly one");
    check(threw, "duplicate semaphore did not throw");
}
#ifndef _WIN32
void permissions(const std::string& name, const std::string& sem) {
    (void)sem;  // macOS does not expose a named semaphore's filesystem mode.
    struct stat info{};
    const int fd = shm_open(name.c_str(), O_RDWR, 0);
    check(fd >= 0, "shm_open inspection failed");
    check(fstat(fd, &info) == 0, "fstat failed");
    close(fd);
    check((info.st_mode & 0777) == 0600, "mapping mode != 0600");
#ifdef __linux__
    const auto path = "/dev/shm/sem." + sem.substr(1);
    check(stat(path.c_str(), &info) == 0, "semaphore stat failed");
    check((info.st_mode & 0777) == 0600, "semaphore mode != 0600");
#endif
}
#endif
void resourcesTest() {
    auto name = uniqueName(shmPrefix(), nullptr);
    const auto semName = uniqueName(semReadyPrefix(), nullptr);
    void* handle = nullptr;
    auto* memory = mapCreate(name, handle);
    auto* sem = semCreate(semName);
#ifndef _WIN32
    permissions(name, semName);
#endif
    mapCollision(name, memory);
    semaphoreCollision(semName, sem);
    semRelease(sem);
    unlinkNames(name, semName, semName);
    mapRetire(memory, handle, name);
    std::cout << "PASS exclusive resources, sentinels and permissions\n";
}
#ifndef _WIN32
std::string exitFile;
void recordExit() {
    const int fd = open(exitFile.c_str(), O_WRONLY | O_APPEND);
    const auto pid = std::to_string(getpid()) + "\n";
    if (fd < 0 || write(fd, pid.data(), pid.size()) != static_cast<ssize_t>(pid.size())) _exit(99);
    close(fd);
}
void failedExecChild() {
    check(atexit(recordExit) == 0, "atexit failed");
    const auto child = spawnWorker("/definitely/missing/vst3-worker", "", "", "");
    int status = 0;
    check(waitpid(static_cast<pid_t>(child), &status, 0) == child, "worker wait failed");
    check(WIFEXITED(status) && WEXITSTATUS(status) == 127, "exec failure status != 127");
    _exit(0);
}
void failedExecTest() {
    char path[] = "/tmp/ipc_platform_exit_XXXXXX";
    const int fd = mkstemp(path);
    check(fd >= 0, "mkstemp failed");
    close(fd);
    exitFile = path;
    const auto child = fork();
    check(child >= 0, "test fork failed");
    if (child == 0) failedExecChild();
    int status = 0;
    check(waitpid(child, &status, 0) == child && status == 0, "child mode failed");
    struct stat info{};
    check(stat(path, &info) == 0, "exit file stat failed");
    unlink(path);
    check(info.st_size == 0, "failed exec ran host atexit handler");
    std::cout << "PASS failed exec never runs host atexit handlers\n";
}
#else
#include "ipc_platform_windows.h"
#endif
int main(int argc, char** argv) {
    try {
#ifdef _WIN32
        if (argc > 1) return windowsChild(argv[1]);
        windowsTest(argv[0]);
#else
        (void)argc; (void)argv;
        umask(0);
        failedExecTest();
#endif
        namesTest();
        resourcesTest();
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << error.what() << '\n';
        return 1;
    }
}
