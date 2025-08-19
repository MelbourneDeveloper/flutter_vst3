// Copyright (c) 2025
//
// VST3 controller implementation for the Dart Reverb plugin.
// This controller manages parameters and UI for the flutter_reverb
// Dart package, providing the control interface for the VST3 host.

#include "dart_reverb_ids.h"
#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ustring.h"
#include "pluginterfaces/vst/ivstmidicontrollers.h"
#include "public.sdk/source/vst/vsteditcontroller.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

// Controller for the Dart Reverb plugin
class DartReverbController : public EditController {
public:
    DartReverbController() = default;
    
    tresult PLUGIN_API initialize(FUnknown* context) override {
        tresult result = EditController::initialize(context);
        if (result != kResultTrue) return result;

        // Add parameters matching the Dart ReverbParameters class
        // Room Size: controls the size of the reverb space
        parameters.addParameter(
            STR16("Room Size"), 
            STR16("%"), 
            0, // stepCount (0 = continuous)
            0.5, // defaultValue (normalized)
            ParameterInfo::kCanAutomate,
            kDartReverbParamRoomSize,
            0, // unitId
            STR16("Room Size")
        );

        // Damping: controls high frequency absorption
        parameters.addParameter(
            STR16("Damping"), 
            STR16("%"), 
            0,
            0.5,
            ParameterInfo::kCanAutomate,
            kDartReverbParamDamping,
            0,
            STR16("Damping")
        );

        // Wet Level: controls the level of reverb signal
        parameters.addParameter(
            STR16("Wet Level"), 
            STR16("%"), 
            0,
            0.3,
            ParameterInfo::kCanAutomate,
            kDartReverbParamWetLevel,
            0,
            STR16("Wet")
        );

        // Dry Level: controls the level of direct signal
        parameters.addParameter(
            STR16("Dry Level"), 
            STR16("%"), 
            0,
            0.7,
            ParameterInfo::kCanAutomate,
            kDartReverbParamDryLevel,
            0,
            STR16("Dry")
        );

        return kResultTrue;
    }

    tresult PLUGIN_API setComponentState(IBStream* state) override {
        if (!state) return kResultFalse;

        // Read parameter values from processor state
        for (int32 i = 0; i < kDartReverbParamCount; ++i) {
            double value = 0.0;
            int32 bytesRead = 0;
            if (state->read(&value, sizeof(value), &bytesRead) == kResultTrue) {
                setParamNormalized(i, value);
            }
        }

        return kResultTrue;
    }

    tresult PLUGIN_API setState(IBStream* state) override {
        return setComponentState(state);
    }

    tresult PLUGIN_API getState(IBStream* state) override {
        if (!state) return kResultFalse;

        // Write current parameter values
        for (int32 i = 0; i < kDartReverbParamCount; ++i) {
            double value = getParamNormalized(i);
            int32 bytesWritten = 0;
            state->write(&value, sizeof(value), &bytesWritten);
        }

        return kResultTrue;
    }

    // Convert normalized parameter values to display strings
    tresult PLUGIN_API getParamStringByValue(ParamID id, ParamValue valueNormalized, String128 string) override {
        switch (id) {
            case kDartReverbParamRoomSize:
            case kDartReverbParamDamping:
            case kDartReverbParamWetLevel:
            case kDartReverbParamDryLevel: {
                // Convert to percentage (0-100%)
                int32 percent = (int32)(valueNormalized * 100.0 + 0.5);
                UString128 wrapper(string);
                wrapper.printInt(percent);
                return kResultTrue;
            }
        }
        return EditController::getParamStringByValue(id, valueNormalized, string);
    }

    // Convert display strings to normalized parameter values  
    tresult PLUGIN_API getParamValueByString(ParamID id, TChar* string, ParamValue& valueNormalized) override {
        switch (id) {
            case kDartReverbParamRoomSize:
            case kDartReverbParamDamping:
            case kDartReverbParamWetLevel:
            case kDartReverbParamDryLevel: {
                UString128 wrapper(string);
                int64 percent = 0;
                if (wrapper.scanInt(percent)) {
                    valueNormalized = percent / 100.0;
                    return kResultTrue;
                }
                break;
            }
        }
        return EditController::getParamValueByString(id, string, valueNormalized);
    }

    // Create view (UI) for the plugin - would integrate with Flutter UI
    IPlugView* PLUGIN_API createView(FIDString name) override {
        if (strcmp(name, ViewType::kEditor) == 0) {
            // TODO: Return Flutter-based UI view
            // For now, return nullptr to use generic host UI
            return nullptr;
        }
        return nullptr;
    }
};

// Factory function for the controller
FUnknown* createDartReverbController(void*) {
    return (IEditController*)new DartReverbController();
}