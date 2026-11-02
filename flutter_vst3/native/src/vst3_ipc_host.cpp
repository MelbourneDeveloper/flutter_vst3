// Copyright (c) 2025
// See vst3_ipc_host.h. Ownership of the memory block passes by semaphore: the
// host may only touch it while the worker isn't busy.

#include "vst3_ipc_host.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <stdexcept>

#include "vst3_ipc_platform.h"

using namespace vst3_ipc;

namespace {

constexpr int kHandshakeTimeoutMs = 5000;
constexpr int kTerminateGraceMs = 500;
constexpr double kMinBudgetSeconds = 0.001;
constexpr double kOfflineBudgetSeconds = 30.0;

/// Names are unique per instance and generation, and within macOS's 31
/// character limit for POSIX names.
std::string uniqueName(const char* prefix, const void* owner) {
    static std::mutex counterMutex;
    static unsigned counter = 0;
    std::lock_guard<std::mutex> lock(counterMutex);
    char name[64];
    std::snprintf(name, sizeof(name), "%s%lx_%llx_%x", prefix, currentProcessId(),
                  static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(owner)) & 0xFFFFFFFFFFFFULL,
                  ++counter & 0xFFFFu);
    return name;
}

void writeSilence(float* outL, float* outR, int numSamples) noexcept {
    std::memset(outL, 0, static_cast<size_t>(numSamples) * sizeof(float));
    std::memset(outR, 0, static_cast<size_t>(numSamples) * sizeof(float));
}

}  // namespace

std::string vst3WorkerPathNextToModule(const std::string& workerName) {
    const std::string path = modulePath();
    const size_t slash = path.find_last_of("\\/");
    const std::string dir = slash == std::string::npos ? std::string(".") : path.substr(0, slash);
#ifdef _WIN32
    return dir + "\\" + workerName + ".exe";
#else
    return dir + "/" + workerName;
#endif
}

Vst3IpcHost::Vst3IpcHost(std::string workerPath, int parameterCount)
    : workerPath_(std::move(workerPath)),
      paramValues_(static_cast<size_t>(parameterCount), 0.0),
      paramKnown_(static_cast<size_t>(parameterCount), 0),
      paramDirty_(static_cast<size_t>(parameterCount), 0) {}

Vst3IpcHost::~Vst3IpcHost() { dispose(); }

int64_t Vst3IpcHost::workerProcessId() const noexcept { return child_ ? childPid(child_) : 0; }

void Vst3IpcHost::configure(double sampleRate, int maxBlockSize, bool offline) {
    offline_ = offline;
    secondsPerSample_ = 1.0 / sampleRate;
    if (running_ && !dead_) {
        reclaimForControl();
        memory_->sampleRate = sampleRate;
        memory_->maxBlockSize = static_cast<uint32_t>(maxBlockSize);
        sendControl(VST3_CMD_CONFIGURE);
        return;
    }
    dispose();
    try {
        start(sampleRate, maxBlockSize);
    } catch (...) {
        dispose();
        throw;
    }
}

void Vst3IpcHost::start(double sampleRate, int maxBlockSize) {
    shmName_ = uniqueName(shmPrefix(), this);
    semReadyName_ = uniqueName(semReadyPrefix(), this);
    semDoneName_ = uniqueName(semDonePrefix(), this);
    memory_ = mapCreate(shmName_, mappingHandle_);
    std::memset(memory_, 0, VST3_SHM_TOTAL_SIZE);
    memory_->version = VST3_SHM_VERSION;
    memory_->sampleRate = sampleRate;
    memory_->maxBlockSize = static_cast<uint32_t>(maxBlockSize);
    memory_->command = VST3_CMD_IDLE;
    memory_->magic = VST3_SHM_MAGIC;
    semReady_ = semCreate(semReadyName_);
    semDone_ = semCreate(semDoneName_);
    child_ = spawnWorker(workerPath_, shmName_, semReadyName_, semDoneName_);
    waitForWorker(kHandshakeTimeoutMs);
    unlinkNames(shmName_, semReadyName_, semDoneName_);
    running_ = true;
    dead_ = false;
    workerBusy_ = false;
    std::copy(paramKnown_.begin(), paramKnown_.end(), paramDirty_.begin());
}

void Vst3IpcHost::waitForWorker(int timeoutMs) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    while (std::chrono::steady_clock::now() < deadline) {
        if (semTimedWait(semDone_, 0.01)) return;
        if (!childAlive(child_)) {
            forgetDeadWorker();
            throw std::runtime_error("Dart worker exited: " + workerPath_);
        }
    }
    throw std::runtime_error("Dart worker timed out: " + workerPath_);
}

void Vst3IpcHost::reclaimForControl() {
    if (!workerBusy_) return;
    waitForWorker(kHandshakeTimeoutMs);
    workerBusy_ = false;
}

void Vst3IpcHost::sendControl(uint32_t command) {
    reclaimForControl();
    memory_->command = command;
    semPost(semReady_);
    waitForWorker(kHandshakeTimeoutMs);
}

void Vst3IpcHost::reset() {
    if (!running_ || dead_) return;
    sendControl(VST3_CMD_RESET);
}

void Vst3IpcHost::stopWorker() noexcept {
    if (!child_) return;
    if (memory_ && semReady_) {
        memory_->command = VST3_CMD_TERMINATE;
        semPost(semReady_);
    }
    childStop(child_, kTerminateGraceMs);
    child_ = 0;
}

void Vst3IpcHost::releaseResources() noexcept {
    if (!memory_) return;
    unlinkNames(shmName_, semReadyName_, semDoneName_);
    if (semReady_) semRelease(semReady_);
    if (semDone_) semRelease(semDone_);
    semReady_ = nullptr;
    semDone_ = nullptr;
    mapRetire(memory_, mappingHandle_, shmName_);
    memory_ = nullptr;
    mappingHandle_ = nullptr;
}

void Vst3IpcHost::dispose() {
    stopWorker();
    releaseResources();
    running_ = false;
    dead_ = false;
    workerBusy_ = false;
}

void Vst3IpcHost::setParameter(int paramId, double value) noexcept {
    if (paramId < 0 || static_cast<size_t>(paramId) >= paramValues_.size()) return;
    const auto id = static_cast<size_t>(paramId);
    paramValues_[id] = value;
    paramKnown_[id] = 1;
    paramDirty_[id] = 1;
}

/// Anything that doesn't fit stays dirty for the next block.
void Vst3IpcHost::flushParameters() noexcept {
    uint32_t write = memory_->hostParamWriteIndex;
    const uint32_t read = memory_->hostParamReadIndex;
    for (size_t id = 0; id < paramDirty_.size() && write - read < VST3_SHM_PARAM_QUEUE_SIZE; ++id) {
        if (!paramDirty_[id]) continue;
        Vst3ParamEvent& event = memory_->hostParams[write % VST3_SHM_PARAM_QUEUE_SIZE];
        event.paramId = static_cast<int32_t>(id);
        event.value = paramValues_[id];
        paramDirty_[id] = 0;
        ++write;
    }
    memory_->hostParamWriteIndex = write;
}

void Vst3IpcHost::noteWorkerLate() noexcept {
    if (!childAlive(child_)) forgetDeadWorker();
}

void Vst3IpcHost::forgetDeadWorker() noexcept {
    if (child_) childReleaseDead(child_);
    child_ = 0;
    dead_ = true;
}

/// Returns true if the block belongs to the host again. A late worker's output
/// is for a block the host already answered with silence, so it's discarded.
bool Vst3IpcHost::reclaimFromLateWorker() noexcept {
    if (!workerBusy_) return true;
    if (semTryWait(semDone_)) {
        workerBusy_ = false;
        return true;
    }
    noteWorkerLate();
    return false;
}

bool Vst3IpcHost::processChunk(const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept {
    if (dead_ || !reclaimFromLateWorker()) {
        writeSilence(outL, outR, numSamples);
        return false;
    }
    flushParameters();
    const size_t bytes = static_cast<size_t>(numSamples) * sizeof(float);
    std::memcpy(memory_->inputL, inL, bytes);
    std::memcpy(memory_->inputR, inR, bytes);
    memory_->numSamples = numSamples;
    memory_->command = VST3_CMD_PROCESS;
    semPost(semReady_);
    const double budget = offline_ ? kOfflineBudgetSeconds : std::max(kMinBudgetSeconds, numSamples * secondsPerSample_);
    if (!semTimedWait(semDone_, budget)) {
        workerBusy_ = true;
        noteWorkerLate();
        writeSilence(outL, outR, numSamples);
        return false;
    }
    std::memcpy(outL, memory_->outputL, bytes);
    std::memcpy(outR, memory_->outputR, bytes);
    return true;
}

bool Vst3IpcHost::process(const float* inL, const float* inR, float* outL, float* outR, int numSamples) noexcept {
    if (!running_) {
        writeSilence(outL, outR, numSamples);
        return false;
    }
    bool complete = true;
    for (int done = 0; done < numSamples;) {
        const int chunk = std::min(numSamples - done, static_cast<int>(VST3_SHM_MAX_SAMPLES));
        complete = processChunk(inL + done, inR + done, outL + done, outR + done, chunk) && complete;
        done += chunk;
    }
    if (!complete) writeSilence(outL, outR, numSamples);
    return complete;
}
