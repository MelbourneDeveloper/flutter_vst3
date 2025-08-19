// Copyright (c) 2025
//
// Factory implementation for the Dart Reverb VST3 plugin.
// This creates instances of the processor and controller that use
// pure Dart audio processing from the flutter_reverb package.

#include "dart_reverb_ids.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"

#define DART_REVERB_VERSION_STR "1.0.0"

using namespace Steinberg;

// Forward declarations from other source files
extern FUnknown* createDartReverbProcessor(void*);
extern FUnknown* createDartReverbController(void*);

bool InitModule() { return true; }
bool DeinitModule() { return true; }

// VST3 plugin factory
BEGIN_FACTORY_DEF("Dart Audio", "https://github.com/dart-lang/vst3-toolkit", "mailto:support@dartaudio.com")

    // Register the Dart Reverb processor
    DEF_CLASS2(INLINE_UID_FROM_FUID(kDartReverbProcessorUID),
               PClassInfo::kManyInstances,                          // cardinality
               kVstAudioEffectClass,                               // category  
               "Flutter Dart Reverb",                              // name
               Vst::kDistributable | Vst::kSimpleModeSupported,    // class flags
               "Fx|Reverb",                                        // subcategory
               DART_REVERB_VERSION_STR,                            // version
               kVstVersionString,                                  // SDK version
               createDartReverbProcessor)                          // factory function

    // Register the Dart Reverb controller
    DEF_CLASS2(INLINE_UID_FROM_FUID(kDartReverbControllerUID),
               PClassInfo::kManyInstances,                          // cardinality
               kVstComponentControllerClass,                        // category
               "Flutter Dart Reverb Controller",                   // name  
               0,                                                  // class flags
               "",                                                 // subcategory
               DART_REVERB_VERSION_STR,                            // version
               kVstVersionString,                                  // SDK version
               createDartReverbController)                         // factory function

END_FACTORY