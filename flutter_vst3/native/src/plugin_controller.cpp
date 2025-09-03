// Copyright (c) 2025
//
// Controller class for the Dart VST host plug‑in. Exposes parameters
// to the host and manages the state of the user interface. Only one
// parameter controlling the output gain is currently provided.

#include "plugin_ids.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "public.sdk/source/vst/vstparameters.h"
#include "pluginterfaces/base/ustring.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

class DvhController : public EditController {
public:
  tresult PLUGIN_API initialize(FUnknown* ctx) override {
    tresult r = EditController::initialize(ctx);
    if (r != kResultTrue) return r;

    // Create a normalized parameter for output gain. Normalized
    // 0.0 -> -60dB, 1.0 -> 0dB. The unit string is in decibels.
    RangeParameter* outGain = new RangeParameter(USTRING("Output Gain"), kParamOutputGain, USTRING("dB"), 0, 1, 0.5);
    parameters.addParameter(outGain);
    return kResultTrue;
  }

};

// Factory function for the controller
FUnknown* createDvhController(void*) { 
  return (IEditController*)new DvhController(); 
}