// Helpers shared by the Vst3IpcHost tests, which run against a real compiled
// Dart worker (probe_worker.dart).
#pragma once

#include <chrono>
#include <cmath>
#include <functional>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "vst3_ipc_host.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

constexpr int kParamStallMs = 0;
constexpr int kParamExit = 1;
constexpr int kParamThrow = 2;
constexpr int kParamProbe = 3;
constexpr int kParamValue = 4;
constexpr int kParamStallNextMs = 5;
constexpr int kParamCount = 6;
constexpr int kProbeSampleRate = 1;
constexpr int kProbeMaxBlock = 2;
constexpr int kProbeBlocks = 3;
constexpr int kProbeResets = 4;
constexpr int kProbeLastValue = 5;

inline std::string gWorker;

inline void check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

inline void checkNear(double actual, double expected, const std::string& message) {
    check(std::fabs(actual - expected) < 1e-3,
          message + ": expected " + std::to_string(expected) + ", got " + std::to_string(actual));
}

struct Block {
    std::vector<float> inL, inR, outL, outR;
    explicit Block(int size, float value = 0.25f) : inL(size, value), inR(size, value), outL(size, 9.f), outR(size, 9.f) {}
    bool render(Vst3IpcHost& host) {
        return host.process(inL.data(), inR.data(), outL.data(), outR.data(), static_cast<int>(inL.size()));
    }
};

inline double probe(Vst3IpcHost& host, int which) {
    host.setParameter(kParamProbe, which);
    Block block(16);
    check(block.render(host), "probe block was late");
    return block.outR[0];
}

inline double msSince(std::chrono::steady_clock::time_point start) {
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
}

inline bool workerGone(int64_t pid) {
#ifdef _WIN32
    HANDLE handle = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(pid));
    if (!handle) return true;
    const bool gone = WaitForSingleObject(handle, 0) == WAIT_OBJECT_0;
    CloseHandle(handle);
    return gone;
#else
    return kill(static_cast<pid_t>(pid), 0) != 0;
#endif
}

inline bool waitUntilGone(int64_t pid, int timeoutMs) {
    const auto start = std::chrono::steady_clock::now();
    while (msSince(start) < timeoutMs) {
        if (workerGone(pid)) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    return false;
}

using IpcTests = std::vector<std::pair<std::string, std::function<void()>>>;

/// Tests of how the host behaves when its worker is late, dead or failing.
IpcTests recoveryTests();
