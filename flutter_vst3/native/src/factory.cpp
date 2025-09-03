// Copyright (c) 2025
//
// Factory implementation for the Dart VST host plug‑in. Registers
// processor and controller classes with Steinberg’s module factory.

#include "plugin_ids.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"

#define FULL_VERSION_STR "1.0.0"

using namespace Steinberg;

extern FUnknown* createDvhProcessor(void*);
extern FUnknown* createDvhController(void*);

bool InitModule() { return true; }
bool DeinitModule() { return true; }

BEGIN_FACTORY_DEF("YourOrg","https://your.org","support@your.org")

DEF_CLASS2(INLINE_UID_FROM_FUID(kProcessorUID),
    PClassInfo::kManyInstances, kVstAudioEffectClass, "DartVstHost",
    Vst::kDistributable | Vst::kSimpleModeSupported,
    "Instrument|Fx", FULL_VERSION_STR, kVstVersionString, createDvhProcessor)

DEF_CLASS2(INLINE_UID_FROM_FUID(kControllerUID),
    PClassInfo::kManyInstances, kVstComponentControllerClass, "DartVstHostController",
    0, "", FULL_VERSION_STR, kVstVersionString, createDvhController)

END_FACTORY