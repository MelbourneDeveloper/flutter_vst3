// Round-trip tests of Vst3IpcHost against a real compiled Dart worker.
//
// Usage: ipc_host_test <path to probe_worker> [--host-then-die <pid file>]
// Every failure exits non-zero.

#include <cstdio>
#include <cstdlib>
#include <fstream>

#include "ipc_test_support.h"

namespace {

void testRoundTrip() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 512, true);
    Block block(512, 0.25f);
    check(block.render(host), "block was late");
    for (float sample : block.outL) checkNear(sample, 0.5, "output is the worker's output");
    checkNear(probe(host, kProbeSampleRate), 48000.0, "worker saw the sample rate");
    checkNear(probe(host, kProbeMaxBlock), 512.0, "worker saw the block size");
}

/// B2: the live worker must see changes to rate and block size.
void testReconfigure() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(44100.0, 512, true);
    const int64_t pid = host.workerProcessId();
    host.setParameter(kParamValue, 0.75);
    Block block(16);
    check(block.render(host), "block was late");
    host.configure(96000.0, 2048, true);
    check(host.workerProcessId() == pid, "reconfigure should keep the worker");
    checkNear(probe(host, kProbeSampleRate), 96000.0, "sample rate after reconfigure");
    checkNear(probe(host, kProbeMaxBlock), 2048.0, "block size after reconfigure");
    checkNear(probe(host, kProbeLastValue), 0.75, "parameters survive reconfigure");
}

/// Parameters set before the worker exists must reach it.
void testParametersReplayToNewWorker() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.setParameter(kParamValue, 0.625);
    host.configure(48000.0, 64, true);
    checkNear(probe(host, kProbeLastValue), 0.625, "value set before start");
    host.dispose();
    host.configure(48000.0, 64, true);
    checkNear(probe(host, kProbeLastValue), 0.625, "value replayed to a restarted worker");
}

/// B3: failed startup throws quickly and leaves nothing behind.
void testStartupFailure(const std::string& badPath, const char* label) {
    Vst3IpcHost host(badPath, kParamCount);
    const auto start = std::chrono::steady_clock::now();
    bool threw = false;
    try {
        host.configure(48000.0, 512, false);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    check(threw, std::string(label) + ": configure should throw");
    check(msSince(start) < 1000.0, std::string(label) + ": failure should be fast");
    check(!host.isRunning(), std::string(label) + ": host should not be running");
    check(host.workerProcessId() == 0, std::string(label) + ": child should be gone");
    Block block(16);
    check(!block.render(host), std::string(label) + ": rendering should report failure");
    checkNear(block.outL[0], 0.0, std::string(label) + ": output should be silent");
}

/// B4: blocks over the shared buffer size are processed completely.
void testOversizedBlock() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 10000, true);
    Block block(10000);
    for (int i = 0; i < 10000; ++i) block.inL[static_cast<size_t>(i)] = static_cast<float>(i) / 10000.0f;
    check(block.render(host), "oversized block was late");
    for (int i = 0; i < 10000; ++i) {
        checkNear(block.outL[static_cast<size_t>(i)], 2.0 * i / 10000.0, "sample " + std::to_string(i));
    }
    checkNear(probe(host, kProbeBlocks), 4.0, "10000 samples take 3 chunks, plus this probe");
}

/// B5: instances have separate DSP state and independent lifetimes.
void testInstancesAreIsolated() {
    Vst3IpcHost a(gWorker, kParamCount);
    Vst3IpcHost b(gWorker, kParamCount);
    a.configure(44100.0, 128, true);
    b.configure(96000.0, 256, true);
    check(a.workerProcessId() != b.workerProcessId(), "each instance has its own worker");
    a.setParameter(kParamValue, 0.1);
    b.setParameter(kParamValue, 0.9);
    Block block(16);
    check(block.render(a), "render a");
    check(block.render(b), "render b");
    checkNear(probe(a, kProbeSampleRate), 44100.0, "a keeps its sample rate");
    checkNear(probe(b, kProbeSampleRate), 96000.0, "b keeps its sample rate");
    checkNear(probe(a, kProbeLastValue), 0.1, "a keeps its parameter");
    checkNear(probe(b, kProbeLastValue), 0.9, "b keeps its parameter");
    a.dispose();
    check(block.render(b), "b must survive disposing a");
    checkNear(block.outL[0], 0.5, "b output after disposing a");
}

/// B10: reset reaches the DSP.
void testReset() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.reset();  // Must be harmless with no worker.
    host.configure(48000.0, 64, true);
    host.reset();
    host.reset();
    checkNear(probe(host, kProbeResets), 2.0, "both resets reached the DSP");
}

/// B9: the reader's memory stays readable after dispose, and shows as dead.
void testMemoryStaysReadableAfterDispose() {
    std::vector<Vst3SharedMemory*> blocks;
    for (int i = 0; i < 3; ++i) {
        Vst3IpcHost host(gWorker, kParamCount);
        host.configure(48000.0, 64, true);
        Vst3SharedMemory* memory = host.memory();
        check(memory->magic == VST3_SHM_MAGIC, "live block has the magic word");
        blocks.push_back(memory);
        host.dispose();
        check(memory->magic == 0, "disposed block has no magic word");
    }
    check(blocks[0] == blocks[1] && blocks[1] == blocks[2], "retired blocks are reused, so the cost is bounded");
}

void testDisposeStopsWorker() {
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 64, true);
    const int64_t pid = host.workerProcessId();
    host.dispose();
    host.dispose();
    check(host.workerProcessId() == 0, "no worker after dispose");
    check(waitUntilGone(pid, 2000), "worker process exited");
}

/// Inherited host descriptors must not leak into the worker.
void testWorkerDoesNotInheritDescriptors() {
#ifndef _WIN32
    int fds[2];
    check(pipe(fds) == 0, "pipe");
    Vst3IpcHost host(gWorker, kParamCount);
    host.configure(48000.0, 64, true);
    close(fds[1]);
    char byte = 0;
    alarm(5);
    const ssize_t got = read(fds[0], &byte, 1);
    alarm(0);
    close(fds[0]);
    check(got == 0, "worker kept the host's descriptor open");
#endif
}

/// B8: run as a child by testWorkerExitsWhenHostDies, this dies without cleanup.
int hostThenDie(const std::string& pidFile) {
    Vst3IpcHost* host = new Vst3IpcHost(gWorker, kParamCount);
    host->configure(48000.0, 64, true);
    std::ofstream(pidFile) << host->workerProcessId();
#ifdef _WIN32
    TerminateProcess(GetCurrentProcess(), 9);
#else
    kill(getpid(), SIGKILL);
#endif
    return 0;
}

void testWorkerExitsWhenHostDies(const std::string& self) {
    const std::string pidFile = self + ".pid";
    std::remove(pidFile.c_str());
#ifdef _WIN32
    const std::string cmd = "\"\"" + self + "\" \"" + gWorker + "\" --host-then-die \"" + pidFile + "\"\"";
#else
    const std::string cmd = "\"" + self + "\" \"" + gWorker + "\" --host-then-die \"" + pidFile + "\"";
#endif
    const int childStatus = std::system(cmd.c_str());
    check(childStatus != 0, "child host should have died by signal");
    int64_t pid = 0;
    std::ifstream(pidFile) >> pid;
    std::remove(pidFile.c_str());
    check(pid > 0, "child host should report its worker");
    check(waitUntilGone(pid, 5000), "worker must exit when its host dies");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <probe_worker>\n", argv[0]);
        return 2;
    }
    gWorker = argv[1];
    if (argc == 4 && std::string(argv[2]) == "--host-then-die") return hostThenDie(argv[3]);
    const std::string self = argv[0];

    IpcTests tests = {
        {"round trip", testRoundTrip},
        {"B2 reconfigure reaches the worker", testReconfigure},
        {"B3 missing worker fails fast", [] { testStartupFailure(gWorker + ".missing", "missing"); }},
        {"B4 oversized block", testOversizedBlock},
        {"B5 instances are isolated", testInstancesAreIsolated},
        {"B8 worker exits when the host dies", [&] { testWorkerExitsWhenHostDies(self); }},
        {"B9 memory stays readable after dispose", testMemoryStaysReadableAfterDispose},
        {"B10 reset reaches the DSP", testReset},
        {"parameters replay to a new worker", testParametersReplayToNewWorker},
        {"dispose stops the worker", testDisposeStopsWorker},
        {"worker does not inherit descriptors", testWorkerDoesNotInheritDescriptors},
    };
    for (auto& test : recoveryTests()) tests.push_back(std::move(test));
    int failures = 0;
    for (const auto& test : tests) {
        try {
            test.second();
            std::printf("PASS %s\n", test.first.c_str());
        } catch (const std::exception& error) {
            ++failures;
            std::printf("FAIL %s: %s\n", test.first.c_str(), error.what());
        }
        std::fflush(stdout);
    }
    std::printf("%d of %zu failed\n", failures, tests.size());
    return failures == 0 ? 0 : 1;
}
