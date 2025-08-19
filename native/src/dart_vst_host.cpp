// Copyright (c) 2025
//
// This file implements a minimal VST3 hosting layer exposing a C API
// suitable for use from Dart via FFI. It loads VST3 modules using
// Steinberg’s public hosting API and wraps components in opaque
// handles. Audio processing is provided for stereo 32‑bit floating
// point buffers. MIDI note on/off events and parameter changes are
// queued into the component prior to each process call.

#include "dart_vst_host.h"

#include <memory>
#include <string>
#include <vector>
#include <mutex>

#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivsthostapplication.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/vsttypes.h"
#include "pluginterfaces/vst/vstspeaker.h"
#include "pluginterfaces/vst/ivstmessage.h"

#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/vsteventshelper.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/vst/utility/stringconvert.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

// Host state object storing global context for a set of plugins. It
// owns a HostApplication which can be queried by loaded plug‑ins.
struct DVH_HostState {
  double sr;
  int32 maxBlock;
  HostApplication hostApp;
  DVH_HostState(double s, int32 m) : sr(s), maxBlock(m) {
    Vst::PluginContextFactory::instance().setPluginContext(&hostApp);
  }
};

// Per‑plugin state storing loaded module, component and controller
// interfaces along with parameter change queues and event lists.
struct DVH_PluginState {
  std::shared_ptr<VST3::Hosting::Module> module;
  VST3::Hosting::ClassInfo classInfo;
  IPtr<IComponent> component;
  IPtr<IAudioProcessor> processor;
  IPtr<IEditController> controller;
  IPtr<IConnectionPoint> compCP;
  IPtr<IConnectionPoint> ctrlCP;

  ParameterChanges inputParamChanges;
  ParameterChanges outputParamChanges;
  EventList inputEvents;

  ProcessSetup setup{};
  bool active{false};

  std::mutex mtx;

  DVH_PluginState()
  : inputParamChanges(64),
    outputParamChanges(64),
    inputEvents(128) {}
};

// Utility converting tresult into 0/1 for C API. Steinberg returns
// kResultTrue on success and kResultFalse or error codes on failure.
static int32_t toOK(tresult r) { return r == kResultTrue ? 1 : 0; }

extern "C" {

// Create a new host state with the given sample rate and maximum
// block size. This sets up the VST context factory to point at
// HostApplication for plug‑ins to query host information.
DVH_Host dvh_create_host(double sample_rate, int32_t max_block) {
  auto* h = new DVH_HostState(sample_rate, max_block);
  return (DVH_Host)h;
}

// Destroy a previously created host. Frees all resources. Plug‑ins
// loaded with this host must be destroyed before destroying the host.
void dvh_destroy_host(DVH_Host host) {
  if (!host) return;
  delete (DVH_HostState*)host;
}

// Load a VST3 plug‑in from a module path. Optionally specify a class
// UID string; if null or empty the first Audio Module Class is used.
// On success a new DVH_PluginState is allocated and returned. On
// failure returns nullptr.
DVH_Plugin dvh_load_plugin(DVH_Host host, const char* module_path_utf8, const char* class_uid_or_null) {
  if (!host || !module_path_utf8) return nullptr;
  auto* hs = (DVH_HostState*)host;

  std::string err;
  auto mod = VST3::Hosting::Module::create(module_path_utf8, err);
  if (!mod) return nullptr;

  VST3::Hosting::ClassInfo chosen;
  bool found = false;
  for (auto& ci : mod->getFactory().classInfos()) {
    if (class_uid_or_null && *class_uid_or_null) {
      if (ci.ID().toString() == std::string(class_uid_or_null)) {
        chosen = ci;
        found = true;
        break;
      }
    } else {
      if (ci.category() == std::string("Audio Module Class")) {
        chosen = ci;
        found = true;
        break;
      }
    }
  }
  if (!found) return nullptr;

  auto plugProvider = std::make_shared<Vst::PlugProvider>(mod->getFactory(), chosen, true);
  if (!plugProvider->initialize()) return nullptr;

  auto* ps = new DVH_PluginState();
  ps->module = mod;
  ps->classInfo = chosen;
  ps->component = plugProvider->getComponentPtr();
  ps->controller = plugProvider->getControllerPtr();

  if (!ps->component) {
    delete ps;
    return nullptr;
  }
  ps->processor = Steinberg::FUnknownPtr<IAudioProcessor>(ps->component);
  if (!ps->processor) {
    delete ps;
    return nullptr;
  }

  ps->component->initialize(&((DVH_HostState*)host)->hostApp);
  if (ps->controller)
    ps->controller->initialize(&((DVH_HostState*)host)->hostApp);

  // Connect component and controller via IConnectionPoint if both
  // expose it. This is necessary for parameter automation to flow.
  ps->component->queryInterface(IConnectionPoint::iid, (void**)&ps->compCP);
  if (ps->controller)
    ps->controller->queryInterface(IConnectionPoint::iid, (void**)&ps->ctrlCP);
  if (ps->compCP && ps->ctrlCP) {
    ps->compCP->connect(ps->ctrlCP);
    ps->ctrlCP->connect(ps->compCP);
  }

  return (DVH_Plugin)ps;
}

// Unload a previously loaded plug‑in. Terminates the component and
// controller and frees the DVH_PluginState. Does nothing if p is
// nullptr.
void dvh_unload_plugin(DVH_Plugin p) {
  if (!p) return;
  auto* ps = (DVH_PluginState*)p;
  if (ps->active) {
    ps->processor->setProcessing(false);
    ps->component->setActive(false);
  }
  if (ps->compCP && ps->ctrlCP) {
    ps->compCP->disconnect(ps->ctrlCP);
    ps->ctrlCP->disconnect(ps->compCP);
  }
  if (ps->controller) ps->controller->terminate();
  if (ps->component) ps->component->terminate();
  delete ps;
}

// Activate processing for a plug‑in. Sets up bus arrangements for
// stereo input/output, configures the process setup and sets the
// component active. Returns 1 on success.
int32_t dvh_resume(DVH_Plugin p, double sample_rate, int32_t max_block) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  std::lock_guard<std::mutex> g(ps->mtx);

  SpeakerArrangement inArr = SpeakerArr::kStereo;
  SpeakerArrangement outArr = SpeakerArr::kStereo;
  if (ps->processor->setBusArrangements(&inArr, 1, &outArr, 1) != kResultTrue) return 0;

  ps->component->activateBus(kAudio, kInput, 0, true);
  ps->component->activateBus(kAudio, kOutput, 0, true);

  ps->setup.processMode = kRealtime;
  ps->setup.symbolicSampleSize = kSample32;
  ps->setup.maxSamplesPerBlock = max_block;
  ps->setup.sampleRate = sample_rate;

  if (ps->processor->setupProcessing(ps->setup) != kResultTrue) return 0;
  if (ps->component->setActive(true) != kResultTrue) return 0;
  if (ps->processor->setProcessing(true) != kResultTrue) return 0;

  ps->active = true;
  return 1;
}

// Suspend processing for a plug‑in. Deactivates processing and the
// component. Returns 1 on success.
int32_t dvh_suspend(DVH_Plugin p) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  std::lock_guard<std::mutex> g(ps->mtx);
  if (!ps->active) return 1;
  ps->processor->setProcessing(false);
  ps->component->setActive(false);
  ps->active = false;
  return 1;
}

// Process a block of stereo audio. Copies input buffers into the
// plug‑in’s buffers, calls process(), then copies the output back
// out. Parameter changes and MIDI events are consumed each block.
int32_t dvh_process_stereo_f32(DVH_Plugin p,
                               const float* inL, const float* inR,
                               float* outL, float* outR,
                               int32_t num_frames) {
  if (!p || !inL || !inR || !outL || !outR || num_frames <= 0) return 0;
  auto* ps = (DVH_PluginState*)p;
  std::lock_guard<std::mutex> g(ps->mtx);

  float* outChannels[2] = { outL, outR };
  const float* inChannels[2] = { inL, inR };

  AudioBusBuffers inBuf{};
  inBuf.numChannels = 2;
  inBuf.channelBuffers32 = const_cast<float**>(inChannels);

  AudioBusBuffers outBuf{};
  outBuf.numChannels = 2;
  outBuf.channelBuffers32 = outChannels;

  ProcessData data{};
  data.processMode = ps->setup.processMode;
  data.symbolicSampleSize = ps->setup.symbolicSampleSize;
  data.numSamples = num_frames;

  data.numInputs = 1;
  data.inputs = &inBuf;
  data.numOutputs = 1;
  data.outputs = &outBuf;

  data.inputParameterChanges = &ps->inputParamChanges;
  data.outputParameterChanges = &ps->outputParamChanges;
  data.inputEvents = &ps->inputEvents;

  auto r = ps->processor->process(data);

  ps->inputParamChanges.clearQueue();
  ps->outputParamChanges.clearQueue();
  ps->inputEvents.clear();

  return toOK(r);
}

// Queue a note on event for the plug‑in. The event is added to the
// inputEvents list and consumed on the next process() call. Returns
// 1 on success.
int32_t dvh_note_on(DVH_Plugin p, int32_t channel, int32_t note, float velocity) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  Vst::Event e{};
  e.type = Vst::Event::kNoteOnEvent;
  e.sampleOffset = 0;
  e.noteOn.channel = (int16)channel;
  e.noteOn.pitch = (int16)note;
  e.noteOn.velocity = velocity;
  return toOK(ps->inputEvents.addEvent(e));
}

// Queue a note off event for the plug‑in. Returns 1 on success.
int32_t dvh_note_off(DVH_Plugin p, int32_t channel, int32_t note, float velocity) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  Vst::Event e{};
  e.type = Vst::Event::kNoteOffEvent;
  e.sampleOffset = 0;
  e.noteOff.channel = (int16)channel;
  e.noteOff.pitch = (int16)note;
  e.noteOff.velocity = velocity;
  return toOK(ps->inputEvents.addEvent(e));
}

// Retrieve the number of parameters defined by the plug‑in’s
// controller. Returns zero if no controller is present.
int32_t dvh_param_count(DVH_Plugin p) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;
  return ps->controller->getParameterCount();
}

// Helper to copy UTF‑8 strings into user provided buffers. Ensures
// null‑termination and truncates if necessary.
static void copy_utf8(const std::string& s, char* out, int32_t cap) {
  if (!out || cap <= 0) return;
  auto n = (int32_t)s.size();
  if (n >= cap) n = cap - 1;
  memcpy(out, s.data(), (size_t)n);
  out[n] = 0;
}

// Retrieve parameter information by index. Fills out the parameter
// ID and copies the title and units into provided UTF‑8 buffers.
int32_t dvh_param_info(DVH_Plugin p, int32_t index,
                       int32_t* id_out,
                       char* title_utf8, int32_t title_cap,
                       char* units_utf8, int32_t units_cap) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;
  ParameterInfo pi{};
  if (ps->controller->getParameterInfo(index, pi) != kResultTrue) return 0;
  if (id_out) *id_out = (int32_t)pi.id;
  std::string title, units;
  {
    auto t = Steinberg::Vst::StringConvert::convert(pi.title);
    title = t;
    auto u = Steinberg::Vst::StringConvert::convert(pi.units);
    units = u;
  }
  copy_utf8(title, title_utf8, title_cap);
  copy_utf8(units, units_utf8, units_cap);
  return 1;
}

// Get the current normalized value of a parameter. Returns 0.0 if
// the controller is not present.
float dvh_get_param_normalized(DVH_Plugin p, int32_t param_id) {
  if (!p) return 0.f;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0.f;
  return (float)ps->controller->getParamNormalized((ParamID)param_id);
}

// Set a normalized value for a parameter. The value is also enqueued
// into the inputParamChanges list so the processor sees the change on
// the next process() call. Returns 1 on success.
int32_t dvh_set_param_normalized(DVH_Plugin p, int32_t param_id, float normalized) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;

  ps->controller->setParamNormalized((ParamID)param_id, normalized);

  int32 idx = 0;
  IParamValueQueue* q = ps->inputParamChanges.addParameterData((ParamID)param_id, idx);
  if (!q) return 0;
  q->addPoint(0, normalized, idx);
  return 1;
}

} // extern "C"