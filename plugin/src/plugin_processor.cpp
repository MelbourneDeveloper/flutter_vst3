// Copyright (c) 2025
//
// Implementation of the audio processor for the Dart VST host plug‑in.
// This component wraps the Graph API and exposes it as a VST3
// processor. It forwards incoming audio and MIDI to the graph and
// outputs the processed result. Automation of the exposed gain
// parameter is mapped to the graph’s gain node.

#include "plugin_ids.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "public.sdk/source/vst/vstaudioeffect.h"

#include "dvh_graph.h"

#define FULL_VERSION_STR "1.0.0"

using namespace Steinberg;
using namespace Steinberg::Vst;

// The processor derives from AudioEffect and holds an instance of the
// graph. It wires up buses and responds to parameter and event
// messages from the host.
class DvhProcessor : public AudioEffect {
public:
  DvhProcessor() { setControllerClass(kControllerUID); }
  ~DvhProcessor() override {
    if (graph_) dvh_graph_destroy(graph_);
  }

  tresult PLUGIN_API initialize(FUnknown* ctx) override {
    tresult r = AudioEffect::initialize(ctx);
    if (r != kResultTrue) return r;

    // Add stereo audio inputs and outputs. Use auxiliary type for
    // inputs to allow both main input and sidechain. Only the main
    // output is required.
    addAudioInput(STR16("Main In"), SpeakerArr::kStereo, kAux);
    addAudioInput(STR16("Sidechain"), SpeakerArr::kStereo, kAux);
    addAudioOutput(STR16("Main Out"), SpeakerArr::kStereo, kMain);

    // MIDI input for note events
    addEventInput(STR16("MIDI In"), 16);

    // Create the graph with a default sample rate and block size. These
    // will be updated in setupProcessing().
    graph_ = dvh_graph_create(48000.0, 1024);
    // Construct a minimal internal graph: input -> mixer -> gain -> output
    int32_t inNode = -1, outNode = -1, mix = -1, gain = -1;
    dvh_graph_add_split(graph_, &inNode);
    dvh_graph_add_mixer(graph_, 3, &mix);
    dvh_graph_add_gain(graph_, 0.0f, &gain);
    dvh_graph_add_split(graph_, &outNode);

    dvh_graph_connect(graph_, inNode, 0, mix, 0);
    dvh_graph_connect(graph_, mix, 0, gain, 0);
    dvh_graph_connect(graph_, gain, 0, outNode, 0);
    dvh_graph_set_io_nodes(graph_, inNode, outNode);
    // Remember the index of the gain node (2) for automation later
    gainNode_ = gain;
    return r;
  }

  tresult PLUGIN_API setBusArrangements(SpeakerArrangement* inputs, int32 numIns,
                                        SpeakerArrangement* outputs, int32 numOuts) override {
    // We only support one stereo output
    if (numOuts != 1 || outputs[0] != SpeakerArr::kStereo) return kResultFalse;
    return kResultTrue;
  }

  tresult PLUGIN_API setupProcessing(ProcessSetup& s) override {
    setup_ = s;
    // Recreate the graph with the actual sample rate and maximum block
    // size when changed. The current implementation does not rebuild
    // nodes on the fly but this could be extended.
    return kResultTrue;
  }

  tresult PLUGIN_API setActive(TBool state) override {
    return AudioEffect::setActive(state);
  }

  tresult PLUGIN_API process(ProcessData& data) override {
    if (!graph_) return kResultFalse;

    // Apply parameter changes from automation. Only one parameter for
    // gain is implemented. Iterate through all incoming changes and
    // update the graph accordingly.
    if (data.inputParameterChanges) {
      int32 listCount = data.inputParameterChanges->getParameterCount();
      for (int32 i = 0; i < listCount; ++i) {
        IParamValueQueue* q = data.inputParameterChanges->getParameterData(i);
        if (!q) continue;
        int32 index;
        ParamValue v;
        int32 sampleOffset;
        // Use the last point in the queue as the effective value
        if (q->getPoint(q->getPointCount() - 1, sampleOffset, v) == kResultTrue) {
          if (q->getParameterId() == kParamOutputGain) {
            dvh_graph_set_param(graph_, gainNode_, 0, (float)v);
          }
        }
      }
    }

    // Dispatch MIDI events
    if (data.inputEvents) {
      int32 n = data.inputEvents->getEventCount();
      for (int32 i = 0; i < n; ++i) {
        Event e;
        if (data.inputEvents->getEvent(i, e) != kResultTrue) continue;
        if (e.type == Event::kNoteOnEvent) dvh_graph_note_on(graph_, -1, e.noteOn.channel, e.noteOn.pitch, e.noteOn.velocity);
        if (e.type == Event::kNoteOffEvent) dvh_graph_note_off(graph_, -1, e.noteOff.channel, e.noteOff.pitch, e.noteOff.velocity);
      }
    }

    // Determine pointers to input and output channel buffers.
    const float* inL = nullptr;
    const float* inR = nullptr;
    if (data.numInputs > 0) {
      auto in0 = &data.inputs[0];
      if (in0->numChannels >= 2) {
        inL = in0->channelBuffers32[0];
        inR = in0->channelBuffers32[1];
      }
    }
    float* outL = nullptr;
    float* outR = nullptr;
    if (data.numOutputs > 0) {
      auto out0 = &data.outputs[0];
      if (out0->numChannels >= 2) {
        outL = out0->channelBuffers32[0];
        outR = out0->channelBuffers32[1];
      }
    }
    if (!outL || !outR) return kResultFalse;
    // Provide zero input if no buffers are connected (e.g. instrument)
    if (!inL || !inR) {
      static float zeros[4096] = {0};
      inL = inR = zeros;
    }

    if (dvh_graph_process_stereo(graph_, inL, inR, outL, outR, data.numSamples) != 1)
      return kResultFalse;

    return kResultTrue;
  }

private:
  DVH_Graph graph_{nullptr};
  ProcessSetup setup_{};
  int32_t gainNode_ = -1;
};

// Factory function for the processor
FUnknown* createDvhProcessor(void*) { 
  return (IAudioProcessor*)new DvhProcessor(); 
}