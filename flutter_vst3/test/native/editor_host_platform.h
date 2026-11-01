// What editor_host_test needs from the OS: parent windows and an event loop.
#pragma once
#include <stdexcept>
#include "base/source/fobject.h"
#include "pluginterfaces/gui/iplugview.h"

inline void check(bool ok, const char* text) {
    if (!ok) throw std::runtime_error(text);
}

/// A host frame that accepts every resize. Linux adds a run loop to this.
class BasicFrame : public Steinberg::IPlugFrame, public Steinberg::FObject {
public:
    REFCOUNT_METHODS(Steinberg::FObject)
    Steinberg::tresult PLUGIN_API queryInterface(const Steinberg::TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, Steinberg::IPlugFrame::iid, Steinberg::IPlugFrame)
        return Steinberg::FObject::queryInterface(iid, obj);
    }
    Steinberg::tresult PLUGIN_API resizeView(Steinberg::IPlugView* view, Steinberg::ViewRect* rect) override {
        return view->onSize(rect);
    }
};

void platformInit();
void platformShutdown();
Steinberg::IPlugFrame* platformFrame();
const char* platformViewType();
long long platformProcessId();
void* platformCreateWindow();
void platformDestroyWindow(void* window);
/// Runs the host's event loop for this long.
void platformPump(int ms);
bool platformHasVisibleChild(void* window);
/// Whether this OS can read back the window's pixels in a test.
bool platformCanCapture();
/// Whether the window shows more than one colour.
bool platformRendered(void* window);
