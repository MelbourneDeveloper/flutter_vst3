// Copyright (c) 2025
// The saved state of a generated plugin: one normalized double per parameter.
// The processor and the controller both read it, and must agree on what's valid.

#pragma once

#include <cmath>
#include <vector>

#include "pluginterfaces/base/ibstream.h"

/// Reads count values from state. Returns false if the stream is short or any
/// value isn't a normalized number, so a caller applies all of a state or none.
inline bool vst3ReadPluginState(Steinberg::IBStream* state, int count, std::vector<double>& values) {
    if (!state) return false;
    std::vector<double> read(static_cast<size_t>(count));
    for (double& value : read) {
        Steinberg::int32 bytesRead = 0;
        if (state->read(&value, sizeof(value), &bytesRead) != Steinberg::kResultTrue || bytesRead != sizeof(value)) {
            return false;
        }
        if (!std::isfinite(value) || value < 0.0 || value > 1.0) return false;
    }
    values.swap(read);
    return true;
}

/// Appends one value to state. Returns false if the stream took less than all of it.
inline bool vst3WritePluginStateValue(Steinberg::IBStream* state, double value) {
    Steinberg::int32 bytesWritten = 0;
    return state->write(&value, sizeof(value), &bytesWritten) == Steinberg::kResultTrue &&
           bytesWritten == sizeof(value);
}
