// End-to-end tests of a real built Echo .vst3 bundle, loaded through the VST3 SDK
// hosting classes the way a DAW loads it, with its real Dart worker.
//
// Usage: plugin_host_test <path to echo.vst3> <path to the bundled worker>
// Every failure exits non-zero.

#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "base/source/fobject.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "public.sdk/source/common/memorystream.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

namespace {

constexpr ParamID kDelay = 0;
constexpr ParamID kFeedback = 1;
constexpr ParamID kMix = 2;
constexpr int32 kBlock = 512;

HostApplication gHost;
std::shared_ptr<VST3::Hosting::Module> gModule;
VST3::UID gProcessorUid;
std::string gWorkerPath;

void check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

using Params = std::vector<std::pair<ParamID, double>>;

class Instance {
public:
    Instance() {
        auto factory = gModule->getFactory();
        factory.setHostContext(&gHost);
        component_ = factory.createInstance<IComponent>(gProcessorUid);
        check(component_ != nullptr, "failed to create the processor");
        check(component_->initialize(&gHost) == kResultOk, "initialize failed");
        processor_ = FUnknownPtr<IAudioProcessor>(component_);
        check(processor_ != nullptr, "component is not an IAudioProcessor");
        component_->activateBus(kAudio, kInput, 0, true);
        component_->activateBus(kAudio, kOutput, 0, true);
    }

    ~Instance() {
        if (active_) deactivate();
        component_->terminate();
    }

    tresult activate(double sampleRate) {
        ProcessSetup setup{kOffline, kSample32, kBlock, sampleRate};
        check(processor_->setupProcessing(setup) == kResultOk, "setupProcessing failed");
        const tresult result = component_->setActive(true);
        if (result != kResultOk) return result;
        processor_->setProcessing(true);
        active_ = true;
        return result;
    }

    void deactivate() {
        processor_->setProcessing(false);
        check(component_->setActive(false) == kResultOk, "setActive(false) failed");
        active_ = false;
    }

    /// Renders one block and returns the left output.
    std::vector<float> render(const std::vector<float>& input, const Params& params = {}, tresult* status = nullptr) {
        std::vector<float> inL(input), inR(input), outL(input.size(), 7.f), outR(input.size(), 7.f);
        float* inPtrs[2] = {inL.data(), inR.data()};
        float* outPtrs[2] = {outL.data(), outR.data()};
        AudioBusBuffers inBus{};
        inBus.numChannels = 2;
        inBus.channelBuffers32 = inPtrs;
        AudioBusBuffers outBus{};
        outBus.numChannels = 2;
        outBus.channelBuffers32 = outPtrs;
        ParameterChanges changes(static_cast<int32>(params.size()) + 1);
        for (const auto& param : params) {
            int32 index = 0;
            auto* queue = changes.addParameterData(param.first, index);
            queue->addPoint(0, param.second, index);
        }
        ProcessData data;
        data.processMode = kOffline;
        data.symbolicSampleSize = kSample32;
        data.numSamples = static_cast<int32>(input.size());
        data.numInputs = 1;
        data.numOutputs = 1;
        data.inputs = &inBus;
        data.outputs = &outBus;
        data.inputParameterChanges = &changes;
        const tresult result = processor_->process(data);
        if (status) *status = result;
        else check(result == kResultOk, "process failed");
        return outL;
    }

    IComponent* component() { return component_.get(); }

private:
    IPtr<IComponent> component_;
    IPtr<IAudioProcessor> processor_;
    bool active_ = false;
};

std::vector<float> silence(int32 size = kBlock) { return std::vector<float>(static_cast<size_t>(size), 0.f); }

std::vector<float> impulse() {
    auto block = silence();
    block[0] = 1.f;
    return block;
}

/// Sends an impulse and returns the sample position of the first echo.
int measureEchoPosition(Instance& instance, int maxSamples) {
    auto out = instance.render(impulse());
    for (int position = 0; position < maxSamples; position += kBlock) {
        for (int i = 0; i < kBlock; ++i) {
            if (std::fabs(out[static_cast<size_t>(i)]) > 0.1f) return position + i;
        }
        out = instance.render(silence());
    }
    return -1;
}

void checkEchoAt(Instance& instance, int expected, const std::string& label) {
    const int position = measureEchoPosition(instance, expected + 4 * kBlock);
    check(std::abs(position - expected) <= 2,
          label + ": expected the echo at " + std::to_string(expected) + ", got " + std::to_string(position));
}

/// Applies wet-only settings with a delay of delayValue, on a silent block.
void applyEchoSettings(Instance& instance, double delayValue) {
    instance.render(silence(), {{kDelay, delayValue}, {kFeedback, 0.0}, {kMix, 1.0}});
}

/// B2: delay time in samples must track the host's sample rate.
void testSampleRateReachesDsp() {
    Instance instance;
    check(instance.activate(48000.0) == kResultOk, "activate failed");
    applyEchoSettings(instance, 0.1);
    checkEchoAt(instance, 4800, "100 ms at 48 kHz");
    instance.deactivate();
    check(instance.activate(96000.0) == kResultOk, "reactivate failed");
    applyEchoSettings(instance, 0.1);
    checkEchoAt(instance, 9600, "100 ms at 96 kHz");
}

/// B3: a missing worker is a failed activation, not silence or a crash.
void testMissingWorkerFailsActivation() {
    const std::string moved = gWorkerPath + ".moved";
    check(std::rename(gWorkerPath.c_str(), moved.c_str()) == 0, "failed to move the worker aside");
    tresult activation = kResultOk;
    tresult processing = kResultOk;
    std::vector<float> out;
    {
        Instance instance;
        activation = instance.activate(48000.0);
        out = instance.render(impulse(), {}, &processing);
    }
    check(std::rename(moved.c_str(), gWorkerPath.c_str()) == 0, "failed to restore the worker");
    check(activation != kResultOk, "activation must fail without a worker");
    check(processing == kNotInitialized, "process must report that it isn't initialized");
    for (float sample : out) check(sample == 0.f, "output must be silent without a worker");
}

/// B5: two instances of one plugin share nothing.
void testInstancesAreIsolated() {
    Instance a;
    Instance b;
    check(a.activate(48000.0) == kResultOk, "activate a");
    check(b.activate(48000.0) == kResultOk, "activate b");
    applyEchoSettings(a, 0.05);
    applyEchoSettings(b, 0.05);
    a.render(impulse());
    for (int i = 0; i < 20; ++i) {
        for (float sample : b.render(silence())) {
            check(sample == 0.f, "an impulse into a must not be heard in b");
        }
    }
    b.render(impulse());
    a.deactivate();
    a.activate(48000.0);
    a.deactivate();
    int heard = 0;
    for (int i = 0; i < 20; ++i) {
        for (float sample : b.render(silence())) heard += std::fabs(sample) > 0.1f ? 1 : 0;
    }
    check(heard > 0, "b must keep working while a is stopped");
}

/// B6: saved state must reach the DSP of a new instance.
void testSavedStateReachesDsp() {
    MemoryStream stream;
    {
        Instance original;
        check(original.activate(48000.0) == kResultOk, "activate original");
        applyEchoSettings(original, 0.25);
        check(original.component()->getState(&stream) == kResultOk, "getState failed");
    }
    stream.seek(0, IBStream::kIBSeekSet, nullptr);
    Instance restored;
    check(restored.component()->setState(&stream) == kResultOk, "setState failed");
    check(restored.activate(48000.0) == kResultOk, "activate restored");
    restored.render(silence());
    checkEchoAt(restored, 12000, "restored 250 ms delay");
}

/// A short state stream must be rejected.
void testTruncatedStateIsRejected() {
    MemoryStream stream;
    double only = 0.5;
    stream.write(&only, sizeof(only), nullptr);
    stream.seek(0, IBStream::kIBSeekSet, nullptr);
    Instance instance;
    check(instance.component()->setState(&stream) != kResultOk, "truncated state must be rejected");
}

/// B10: stopping must clear the tail.
void testDeactivateClearsTail() {
    Instance instance;
    check(instance.activate(48000.0) == kResultOk, "activate");
    applyEchoSettings(instance, 0.05);
    instance.render(impulse());
    instance.deactivate();
    check(instance.activate(48000.0) == kResultOk, "reactivate");
    for (int i = 0; i < 20; ++i) {
        for (float sample : instance.render(silence())) {
            check(sample == 0.f, "a tail from before deactivation must not play");
        }
    }
}

/// B4: a block larger than the shared buffer must be fully rendered.
void testOversizedBlock() {
    Instance instance;
    check(instance.activate(48000.0) == kResultOk, "activate");
    instance.render(silence(), {{kFeedback, 0.0}, {kMix, 0.0}});
    std::vector<float> input(10000, 0.5f);
    const auto out = instance.render(input);
    for (size_t i = 0; i < out.size(); ++i) {
        check(std::fabs(out[i] - 0.5f) < 1e-3f, "sample " + std::to_string(i) + " was not rendered");
    }
}

VST3::UID findProcessor() {
    for (const auto& info : gModule->getFactory().classInfos()) {
        if (info.category() == kVstAudioEffectClass) return info.ID();
    }
    throw std::runtime_error("the module has no audio effect class");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: %s <echo.vst3> <worker>\n", argv[0]);
        return 2;
    }
    std::string error;
    gModule = VST3::Hosting::Module::create(argv[1], error);
    if (!gModule) {
        std::fprintf(stderr, "failed to load %s: %s\n", argv[1], error.c_str());
        return 2;
    }
    gProcessorUid = findProcessor();
    gWorkerPath = argv[2];

    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"B2 sample rate reaches the DSP", testSampleRateReachesDsp},
        {"B3 missing worker fails activation", testMissingWorkerFailsActivation},
        {"B4 oversized block", testOversizedBlock},
        {"B5 instances are isolated", testInstancesAreIsolated},
        {"B6 saved state reaches the DSP", testSavedStateReachesDsp},
        {"B6 truncated state is rejected", testTruncatedStateIsRejected},
        {"B10 deactivate clears the tail", testDeactivateClearsTail},
    };
    int failures = 0;
    for (const auto& test : tests) {
        try {
            test.second();
            std::printf("PASS %s\n", test.first.c_str());
        } catch (const std::exception& failure) {
            ++failures;
            std::printf("FAIL %s: %s\n", test.first.c_str(), failure.what());
        }
        std::fflush(stdout);
    }
    std::printf("%d of %zu failed\n", failures, tests.size());
    return failures == 0 ? 0 : 1;
}
