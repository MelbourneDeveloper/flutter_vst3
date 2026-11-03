// Copyright (c) 2025
// Plugin side of the shared memory bridge to a Dart worker process.
//
// Each plugin instance owns one Vst3IpcHost and so has its own worker, memory
// block and semaphores. Threads:
// - configure, reset and dispose run on the host's non-realtime thread, never
//   concurrently with process (VST3 setActive and terminate rules).
// - setParameter and process run on the audio thread. They never allocate or
//   lock, and process never waits longer than the block's own duration.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "vst3_shared_memory.h"

/// Returns the path of workerName next to the module containing this code.
std::string vst3WorkerPathNextToModule(const std::string& workerName);

class Vst3IpcHost {
public:
    /// Creates an idle host. Nothing is spawned until configure.
    Vst3IpcHost(std::string workerPath, int parameterCount);
    ~Vst3IpcHost();
    Vst3IpcHost(const Vst3IpcHost&) = delete;
    Vst3IpcHost& operator=(const Vst3IpcHost&) = delete;

    /// Starts the worker, or reconfigures a running one. Replays known
    /// parameter values to a new worker. Throws, leaving nothing behind, if the
    /// worker can't start.
    void configure(double sampleRate, int maxBlockSize, bool offline);

    /// Clears DSP state in the worker. Does nothing if no worker is running.
    void reset();

    /// Stops the worker and releases its resources. Safe to call repeatedly.
    void dispose();

    /// Records a parameter value for the next block. Later values win, so
    /// nothing is lost while the worker is late. Unknown ids are ignored.
    void setParameter(int paramId, double value) noexcept;

    /// Renders any number of samples. Returns false, with all of the output
    /// silent, if the worker was late or dead for any part of it.
    bool process(const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept;

    /// True once configure has succeeded and the worker hasn't been seen dead.
    bool isRunning() const noexcept { return running_ && !dead_; }

    /// Memory block for in-process readers, or null when idle. An address taken
    /// from here stays mapped after dispose with a
    /// zero magic word, so a reader can never fault on it.
    Vst3SharedMemory* memory() const noexcept { return memory_; }

    /// Worker process id, or 0 when there is none.
    int64_t workerProcessId() const noexcept;

private:
    bool processChunk(const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept;
    bool reclaimFromLateWorker() noexcept;
    void flushParameters() noexcept;
    void noteWorkerLate() noexcept;
    void forgetDeadWorker() noexcept;
    void reclaimForControl();
    void start(double sampleRate, int maxBlockSize);
    void sendControl(uint32_t command);
    void waitForWorker(int timeoutMs);
    void stopWorker() noexcept;
    void releaseResources() noexcept;

    std::string workerPath_;
    std::string shmName_;
    std::string semReadyName_;
    std::string semDoneName_;
    Vst3SharedMemory* memory_ = nullptr;
    void* mappingHandle_ = nullptr;
    void* semReady_ = nullptr;
    void* semDone_ = nullptr;
    intptr_t child_ = 0;
    bool running_ = false;
    bool dead_ = false;
    bool workerBusy_ = false;
    double secondsPerSample_ = 0.0;
    bool offline_ = false;
    std::vector<double> paramValues_;
    std::vector<char> paramKnown_;
    std::vector<char> paramDirty_;
};
