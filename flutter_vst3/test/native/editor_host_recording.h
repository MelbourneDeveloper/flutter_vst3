#pragma once
#include <vector>
#include <cstdio>
#include "editor_host_platform.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
using namespace Steinberg;
using namespace Steinberg::Vst;
struct RecordedEdit { char kind; ParamID id; ParamValue value; };
class RecordingHandler : public IComponentHandler, public FObject {
public:
    std::vector<RecordedEdit> events;
    REFCOUNT_METHODS(FObject)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, IComponentHandler::iid, IComponentHandler)
        return FObject::queryInterface(iid, obj);
    }
    tresult PLUGIN_API beginEdit(ParamID id) override {
        events.push_back({'b', id, 0}); return kResultTrue;
    }
    tresult PLUGIN_API performEdit(ParamID id, ParamValue value) override {
        events.push_back({'p', id, value}); return kResultTrue;
    }
    tresult PLUGIN_API endEdit(ParamID id) override {
        events.push_back({'e', id, 0}); return kResultTrue;
    }
    tresult PLUGIN_API restartComponent(int32) override { return kResultTrue; }
    void balanced(double finalValue) {
        check(events.size() >= 3, "drag missing events");
        for (auto event : events) std::fprintf(stderr, "gesture %c(%u,%.17g)\n", event.kind, event.id, event.value);
        check(events.front().kind == 'b' && events.back().kind == 'e', "drag boundaries");
        for (size_t i = 0; i < events.size(); ++i) {
            check(events[i].id == 0, "drag wrong id");
            if (i > 0 && i + 1 < events.size()) {
                check(events[i].kind == 'p', "drag duplicate begin/end");
                check(events[i].value >= 0 && events[i].value <= 1, "drag range");
            }
        }
        check(events[events.size()-2].value > 0.1, "drag did not increase");
        check(events[events.size()-2].value == finalValue, "drag controller value mismatch");
    }
    void exactTriple(double value) {
        check(events.size() == 3, "gesture must contain exactly three events");
        check(events[0].kind == 'b' && events[0].id == 0, "begin(0)");
        check(events[1].kind == 'p' && events[1].id == 0 && events[1].value == value, "perform(0,v)");
        check(events[2].kind == 'e' && events[2].id == 0, "end(0)");
    }
};
