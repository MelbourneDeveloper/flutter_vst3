// Copyright (c) 2025
//
// Unique identifiers for the Dart Reverb VST3 plugin. This plugin
// uses pure Dart audio processing from the flutter_reverb package
// via FFI bridge to create a complete VST3 reverb plugin.

#pragma once
#include "pluginterfaces/base/fplatform.h"
#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/vsttypes.h"

// com.dartaudio.FlutterReverb - Unique GUIDs for Dart Reverb plugin
// These must be globally unique and different from the generic host plugin
static const Steinberg::FUID kDartReverbProcessorUID (0xF1D2A3B4, 0x12340001, 0x56780002, 0x9ABC0003);
static const Steinberg::FUID kDartReverbControllerUID(0xF1D2A3B4, 0x12340004, 0x56780005, 0x9ABC0006);

// Parameter identifiers matching Dart ReverbParameters class
enum DartReverbParams : Steinberg::Vst::ParamID {
    kDartReverbParamRoomSize = 0,
    kDartReverbParamDamping = 1,
    kDartReverbParamWetLevel = 2,
    kDartReverbParamDryLevel = 3,
    kDartReverbParamCount = 4
};