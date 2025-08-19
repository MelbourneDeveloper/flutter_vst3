// Copyright (c) 2025
//
// VST3 processor implementation for the Dart Reverb plugin.
// This processor uses the dart_reverb_bridge to call pure Dart
// reverb processing code via FFI callbacks, implementing a complete
// VST3 plugin powered by flutter_reverb Dart package.

#include "dart_reverb_ids.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "public.sdk/source/vst/vstaudioeffect.h"

#include "dart_reverb_bridge.h"

#define DART_REVERB_VERSION_STR "1.0.0"

using namespace Steinberg;
using namespace Steinberg::Vst;

// VST3 parameter IDs for the reverb (matching Dart ReverbParameters)
enum {
    kParamRoomSize = 0,
    kParamDamping = 1,
    kParamWetLevel = 2,
    kParamDryLevel = 3,
    kParamCount = 4
};

// The processor derives from AudioEffect and uses the Dart reverb bridge
// to process audio through pure Dart code in the flutter_reverb package
class DartReverbProcessor : public AudioEffect {
public:
    DartReverbProcessor() { 
        setControllerClass(kDartReverbControllerUID); 
    }
    
    ~DartReverbProcessor() override {
        dart_reverb_dispose();
    }

    tresult PLUGIN_API initialize(FUnknown* ctx) override {
        tresult r = AudioEffect::initialize(ctx);
        if (r != kResultTrue) return r;

        // Add stereo audio input and output
        addAudioInput(STR16("Stereo In"), SpeakerArr::kStereo);
        addAudioOutput(STR16("Stereo Out"), SpeakerArr::kStereo);

        // Initialize with default values - will be updated in setupProcessing
        dart_reverb_initialize(48000.0, 1024);
        
        return r;
    }

    tresult PLUGIN_API setBusArrangements(SpeakerArrangement* inputs, int32 numIns,
                                          SpeakerArrangement* outputs, int32 numOuts) override {
        // We only support stereo input and output
        if (numIns != 1 || numOuts != 1) return kResultFalse;
        if (inputs[0] != SpeakerArr::kStereo || outputs[0] != SpeakerArr::kStereo) {
            return kResultFalse;
        }
        return kResultTrue;
    }

    tresult PLUGIN_API setupProcessing(ProcessSetup& s) override {
        setup_ = s;
        
        // Re-initialize Dart processor with actual sample rate and block size
        dart_reverb_initialize(s.sampleRate, s.maxSamplesPerBlock);
        
        return kResultTrue;
    }

    tresult PLUGIN_API setActive(TBool state) override {
        if (state) {
            dart_reverb_reset();
        }
        return AudioEffect::setActive(state);
    }

    tresult PLUGIN_API process(ProcessData& data) override {
        // Apply parameter changes from automation
        if (data.inputParameterChanges) {
            int32 listCount = data.inputParameterChanges->getParameterCount();
            for (int32 i = 0; i < listCount; ++i) {
                IParamValueQueue* q = data.inputParameterChanges->getParameterData(i);
                if (!q) continue;
                
                ParamID paramId = q->getParameterId();
                int32 pointCount = q->getPointCount();
                
                // Use the last point in the queue as the effective value
                int32 sampleOffset;
                ParamValue value;
                if (q->getPoint(pointCount - 1, sampleOffset, value) == kResultTrue) {
                    if (paramId < kParamCount) {
                        dart_reverb_set_parameter(paramId, value);
                    }
                }
            }
        }

        // Get input and output buffer pointers
        const float* inL = nullptr;
        const float* inR = nullptr;
        if (data.numInputs > 0 && data.inputs[0].numChannels >= 2) {
            inL = data.inputs[0].channelBuffers32[0];
            inR = data.inputs[0].channelBuffers32[1];
        }
        
        float* outL = nullptr;
        float* outR = nullptr;
        if (data.numOutputs > 0 && data.outputs[0].numChannels >= 2) {
            outL = data.outputs[0].channelBuffers32[0];
            outR = data.outputs[0].channelBuffers32[1];
        }
        
        if (!outL || !outR) return kResultFalse;
        
        // Provide zero input if no input connected
        static float zeros[4096] = {0};
        if (!inL || !inR) {
            inL = inR = zeros;
        }

        // Process audio through Dart reverb
        if (!dart_reverb_process_stereo(inL, inR, outL, outR, data.numSamples)) {
            // If Dart processing failed, pass through input
            if (inL != zeros) {
                memcpy(outL, inL, data.numSamples * sizeof(float));
                memcpy(outR, inR, data.numSamples * sizeof(float));
            } else {
                // Clear output if no input
                memset(outL, 0, data.numSamples * sizeof(float));
                memset(outR, 0, data.numSamples * sizeof(float));
            }
        }

        return kResultTrue;
    }

    tresult PLUGIN_API setState(IBStream* state) override {
        if (!state) return kResultFalse;
        
        // Read parameter values from saved state
        for (int32 i = 0; i < kParamCount; ++i) {
            double value = 0.0;
            int32 bytesRead = 0;
            if (state->read(&value, sizeof(value), &bytesRead) == kResultTrue) {
                dart_reverb_set_parameter(i, value);
            }
        }
        
        return kResultTrue;
    }

    tresult PLUGIN_API getState(IBStream* state) override {
        if (!state) return kResultFalse;
        
        // Write parameter values to state
        for (int32 i = 0; i < kParamCount; ++i) {
            double value = dart_reverb_get_parameter(i);
            int32 bytesWritten = 0;
            state->write(&value, sizeof(value), &bytesWritten);
        }
        
        return kResultTrue;
    }

private:
    ProcessSetup setup_{};
};

// Factory function for the processor
FUnknown* createDartReverbProcessor(void*) { 
    return (IAudioProcessor*)new DartReverbProcessor(); 
}