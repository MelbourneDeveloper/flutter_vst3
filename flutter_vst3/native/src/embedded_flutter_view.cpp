// Copyright (c) 2025
// Embedded Flutter view for VST3 plugins - Header/Declaration file
// Implementation is in embedded_flutter_view.mm to avoid header conflicts

#include "pluginterfaces/gui/iplugview.h"

namespace Steinberg::Vst {
    // Forward declaration - implementation in .mm file
    IPlugView* createEmbeddedFlutterView();
}