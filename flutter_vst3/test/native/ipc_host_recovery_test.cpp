// How Vst3IpcHost behaves when its worker is late, dead or failing.

#include "ipc_test_support.h"

namespace {

/// B1: a late block must not desynchronize any later block.
void testRecoversAfterLateBlock() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 256, false);
    host.setParameter(kParamStallMs, 200);
    Block late(256, 0.25f);
    check(!late.render(host), "stalled block should be reported late");
    for (float sample : late.outL) checkNear(sample, 0.0, "late block is silent");

    const auto start = std::chrono::steady_clock::now();
    bool recovered = false;
    while (!recovered && msSince(start) < 2000) {
        Block next(256, 0.1f);
        recovered = next.render(host);
        for (float sample : next.outL) checkNear(sample, recovered ? 0.2 : 0.0, "block around the stall");
        if (!recovered) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    check(recovered, "the host never recovered from a late block");
    int rendered = 0;
    for (int i = 0; i < 50; ++i) {
        const float value = 0.01f * static_cast<float>(i + 1);
        Block block(256, value);
        if (!block.render(host)) continue;  // A slow machine may miss a realtime deadline.
        ++rendered;
        checkNear(block.outL[0], value * 2.0, "block returned its own output, not a stale one");
    }
    check(rendered > 0, "no block rendered after recovery");
}

/// B7: a stalled worker costs one block's budget, and later blocks don't wait.
void testStallIsBounded() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 480, false);
    host.setParameter(kParamStallMs, 500);
    Block block(480);
    const auto start = std::chrono::steady_clock::now();
    check(!block.render(host), "stalled block should be reported late");
    const double firstMs = msSince(start);
    check(firstMs < 40.0, "first late block took " + std::to_string(firstMs) + " ms against a 10 ms budget");
    const auto second = std::chrono::steady_clock::now();
    for (int i = 0; i < 100; ++i) block.render(host);
    const double laterMs = msSince(second);
    check(laterMs < 50.0, "100 blocks during a stall took " + std::to_string(laterMs) + " ms");
}

/// B8: a dead worker produces silence without any per-block wait.
void testDeadWorkerIsBounded() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 4096, false);
    const int64_t pid = host.workerProcessId();
    host.setParameter(kParamExit, 1.0);
    Block block(4096);
    check(!block.render(host), "block from a dying worker should be reported late");
    check(waitUntilGone(pid, 2000), "worker should have exited");
    block.render(host);
    check(!host.isRunning(), "host should notice the dead worker");
    host.setParameter(kParamExit, 0.0);
    const auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < 1000; ++i) {
        check(!block.render(host), "dead worker block must be reported");
    }
    const double elapsed = msSince(start);
    check(elapsed < 200.0, "1000 blocks with a dead worker took " + std::to_string(elapsed) + " ms");
    for (float sample : block.outL) checkNear(sample, 0.0, "dead worker output is silent");
    host.configure(48000.0, 4096, true);
    check(host.isRunning(), "configure should start a new worker");
    check(block.render(host), "new worker should render");
    checkNear(block.outL[0], 0.5, "new worker output");
}

/// An exception in the DSP is fatal to the worker and visible to the host.
void testDspExceptionIsDetected() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 4096, false);
    host.setParameter(kParamThrow, 1.0);
    Block block(4096);
    const auto start = std::chrono::steady_clock::now();
    while (host.isRunning() && msSince(start) < 3000) {
        block.render(host);
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    check(!host.isRunning(), "host should notice a worker killed by a DSP exception");
}

/// B7: values set while the worker is late are kept, and the latest one wins.
void testParametersSurviveStall() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 256, false);
    host.setParameter(kParamStallMs, 100);
    Block block(256);
    block.render(host);
    for (int i = 0; i < 1000; ++i) {
        host.setParameter(kParamValue, i / 1000.0);
        block.render(host);
    }
    host.configure(48000.0, 256, true);
    checkNear(probe(host, kProbeLastValue), 0.999, "latest value arrives after the stall");
}

/// A false return means the whole output is silent: that's what the plugin tells
/// the host through its silence flags, so no part may hold audio.
void testPartlyLateBlockIsWhollySilent() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 8192, false);
    host.setParameter(kParamStallNextMs, 500);
    Block block(8192, 0.25f);
    check(!block.render(host), "a block with a late chunk should be reported late");
    for (size_t i = 0; i < block.outL.size(); ++i) {
        check(block.outL[i] == 0.f && block.outR[i] == 0.f, "sample " + std::to_string(i) + " is not silent");
    }
}

/// Worker crashes must not cost the host anything: each restart works, and no
/// process handles build up.
void testCrashCyclesLeakNothing() {
    Vst3IpcHost host(gWorker, kParamCount);
    const auto crashOnce = [&] {
        host.configure(48000.0, 64, false);
        host.setParameter(kParamExit, 0);
        Block good(64, 0.25f);
        const auto waited = std::chrono::steady_clock::now();
        bool rendered = false;
        while (!rendered && msSince(waited) < 2000) rendered = good.render(host);
        check(rendered, "restarted worker never rendered");
        checkNear(good.outL[0], 0.5, "restarted worker output");
        host.setParameter(kParamExit, 1);
        const auto start = std::chrono::steady_clock::now();
        Block block(64);
        while (host.isRunning() && msSince(start) < 5000) block.render(host);
        check(!host.isRunning(), "the host never noticed the crash");
        check(host.workerProcessId() == 0, "a dead worker has no process id");
    };
    crashOnce();
#ifdef _WIN32
    DWORD before = 0, after = 0;
    check(GetProcessHandleCount(GetCurrentProcess(), &before) != 0, "GetProcessHandleCount");
#endif
    for (int i = 0; i < 20; ++i) crashOnce();
#ifdef _WIN32
    check(GetProcessHandleCount(GetCurrentProcess(), &after) != 0, "GetProcessHandleCount");
    check(after < before + 10, "process handles grew from " + std::to_string(before) + " to " + std::to_string(after));
#endif
}

}  // namespace

IpcTests recoveryTests() {
    return {
        {"B1 recovers after a late block", testRecoversAfterLateBlock},
        {"B7 stall is bounded", testStallIsBounded},
        {"B7 parameters survive a stall", testParametersSurviveStall},
        {"B8 dead worker is bounded", testDeadWorkerIsBounded},
        {"DSP exception is detected", testDspExceptionIsDetected},
        {"partly late block is wholly silent", testPartlyLateBlockIsWhollySilent},
        {"crash cycles leak nothing", testCrashCyclesLeakNothing},
    };
}
