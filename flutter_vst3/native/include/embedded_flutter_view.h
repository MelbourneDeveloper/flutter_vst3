// Copyright (c) 2025
// Header for embedded Flutter view factory function

#pragma once

namespace Steinberg::Vst {
    class IPlugView;
    
    // Factory function to create embedded Flutter view
    IPlugView* createEmbeddedFlutterView();
}