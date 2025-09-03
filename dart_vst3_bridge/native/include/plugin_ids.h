// Copyright (c) 2025
//
// Definition of unique identifiers for the Dart VST host plug‑in. The
// processor and controller GUIDs must be globally unique to avoid
// clashes with other plug‑ins. Adjust these values when creating a
// new plug‑in product.

#pragma once
#include "pluginterfaces/base/fplatform.h"
#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/vsttypes.h"

// com.yourorg.DartVstHost
static const Steinberg::FUID kProcessorUID (0xA1B2C3D4, 0x00000001, 0x00000002, 0x00000003);
static const Steinberg::FUID kControllerUID(0xA1B2C3D4, 0x00000004, 0x00000005, 0x00000006);

// Parameter identifiers for the host plug‑in. Currently only one
// parameter controlling the output gain of the main mixer. When you
// add more exposed parameters to the graph they should be listed here.
enum Params : Steinberg::Vst::ParamID {
  kParamOutputGain = 0,
};