#include <algorithm>
#include <cstdio>
#include <memory>
#include <string>
#include "editor_host_platform.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstmessage.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
using namespace Steinberg;
using namespace Steinberg::Vst;
HostApplication host;
std::shared_ptr<VST3::Hosting::Module> module;
VST3::UID controllerUid;
VST3::UID processorUid;
class Wire : public IConnectionPoint, public FObject {
public:
    IConnectionPoint* target{nullptr};
    int64 address{-1}, pid{-1};
    REFCOUNT_METHODS(FObject)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, IConnectionPoint::iid, IConnectionPoint)
        return FObject::queryInterface(iid, obj);
    }
    tresult PLUGIN_API connect(IConnectionPoint*) override { return kResultTrue; }
    tresult PLUGIN_API disconnect(IConnectionPoint*) override { return kResultTrue; }
    tresult PLUGIN_API notify(IMessage* message) override {
        check(std::string(message->getMessageID()) == "Vst3Shm", "H7 unexpected message");
        check(message->getAttributes()->getInt("address", address) == kResultTrue, "H7 address wire type");
        check(message->getAttributes()->getInt("pid", pid) == kResultTrue, "H7 pid wire type");
        check(target->notify(message) == kResultTrue, "H7 controller rejected message");
        return kResultTrue;
    }
};
void foreignPid(IConnectionPoint* receiver) {
    HostMessage foreign; foreign.setMessageID("Vst3Shm");
    foreign.getAttributes()->setInt("address", 123); foreign.getAttributes()->setInt("pid", platformProcessId() + 1);
    check(receiver->notify(&foreign) == kResultTrue, "H7 foreign pid notify");
    puts("PASS H7 foreign pid accepted without crash");
}
void wireActivation(IComponent* component, Wire& wire) {
    FUnknownPtr<IAudioProcessor> processor(component);
    check(processor != nullptr, "H7 processor interface");
    ProcessSetup setup{kOffline, kSample32, 512, 48000};
    check(processor->setupProcessing(setup) == kResultTrue, "H7 setup");
    check(component->setActive(true) == kResultTrue, "H7 activation");
    check(wire.address != 0 && wire.pid == platformProcessId(), "H7 activation wire payload");
    puts("PASS H7 activation sender and forwarding (internal controller address not observable)");
    check(component->setActive(false) == kResultTrue, "H7 deactivate");
}
void sharedMemoryWire() {
    auto factory = module->getFactory();
    auto component = factory.createInstance<IComponent>(processorUid);
    auto controller = factory.createInstance<IEditController>(controllerUid);
    check(component->initialize(&host) == kResultTrue, "H7 component initialize");
    check(controller->initialize(&host) == kResultTrue, "H7 controller initialize");
    FUnknownPtr<IConnectionPoint> sender(component), receiver(controller);
    check(sender && receiver, "H7 interfaces");
    Wire wire; wire.target = receiver; check(sender->connect(&wire) == kResultTrue, "H7 connect");
    wireActivation(component, wire);
    const bool cleared = wire.address == 0;
    foreignPid(receiver);
    sender->disconnect(&wire); controller->terminate(); component->terminate();
    check(cleared, "H7 deactivation payload: processor never sent address 0");
    puts("PASS H7 deactivation payload");
}
struct Editor {
    IPtr<IEditController> controller;
    IPtr<IPlugView> view;
    void* window;
    bool terminated{false};
    Editor() {
        controller = module->getFactory().createInstance<IEditController>(controllerUid);
        check(controller && controller->initialize(&host) == kResultOk, "controller initialize");
        view = owned(controller->createView("editor"));
        check(view != nullptr, "createView");
        window = platformCreateWindow();
        check(view->setFrame(platformFrame()) == kResultTrue, "setFrame");
        check(view->attached(window, platformViewType()) == kResultTrue, "attached");
    }
    ~Editor() {
        view->removed(); view->setFrame(nullptr); view = nullptr;
        if (!terminated) controller->terminate();
        platformDestroyWindow(window);
    }
    int width() {
        ViewRect r; check(view->getSize(&r) == kResultTrue, "getSize"); return r.getWidth();
    }
    bool child() { return platformHasVisibleChild(window); }
};
void rendering(Editor& editor) {
    if (!platformCanCapture()) {
        puts("NOT RUN Rendering: this OS cannot read the window back in a test");
        return;
    }
    check(platformRendered(editor.window), "Rendering: the editor window is one uniform colour");
    puts("PASS Rendering");
}
void concurrent(bool ownerFirst) {
    auto a = std::make_unique<Editor>(); platformPump(500);
    auto b = std::make_unique<Editor>(); platformPump(500);
    check(a->width() == 600 && b->width() == 540, "B13 owner stolen or second editor not native");
    check(a->child() && b->child(), "B13 missing mapped child");
    if (ownerFirst) {
        a.reset(); platformPump(500);
        check(b->width() == 540 && b->child(), "B13 native editor disturbed by owner close");
        check(b->controller->setParamNormalized(0, 0.4) == kResultTrue, "B13 native parameter update");
        b.reset(); auto c = std::make_unique<Editor>(); platformPump(500);
        check(c->width() == 600 && c->child(), "B13 reopen failed");
    } else {
        b.reset(); platformPump(500);
        check(a->width() == 600 && a->child(), "B13 owner disturbed by secondary close");
    }
    puts(ownerFirst ? "PASS B13 owner closed first" : "PASS B13 secondary closed first");
}
void reopenSameView() {
    auto owner = std::make_unique<Editor>(); platformPump(500);
    Editor secondary; platformPump(500);
    ViewRect nativeRect(0, 0, 540, 400);
    secondary.view->onSize(&nativeRect);
    secondary.view->removed(); owner.reset();
    check(secondary.view->attached(secondary.window, platformViewType()) == kResultTrue, "same view reattach");
    platformPump(500);
    check(secondary.width() == 600 && secondary.child(), "same view kept stale native host/size");
    puts("PASS B13 same view chooses Flutter again");
}
void run(const std::string& mode) {
    if (mode == "good") {
        { Editor a; platformPump(15000); check(a.width() == 600 && a.child(), "B12/B14 Dart did not start");
          puts("PASS B12/B14 positive"); rendering(a); }
        concurrent(true); concurrent(false); reopenSameView();
        { Editor a; platformPump(500); a.controller->terminate(); a.terminated = true; }
        puts("PASS controller terminate before view close");
    } else {
        Editor a;
        if (mode == "missing") check(a.width() == 540, "B14 missing AOT did not fall back immediately");
        else { check(mode == "garbage", "unknown mode"); platformPump(13000); }
        platformPump(500);
        check(a.width() == 540 && a.child(), "B14 failed to mount native fallback");
        Editor b; platformPump(500);
        check(b.width() == 540 && b.child(), "B14 second editor did not remain native");
        puts("PASS B14 broken bundle fallback");
    }
}
void loadBundle(const char* path) {
    std::string error; module = VST3::Hosting::Module::create(path, error);
    check(module != nullptr, error.c_str());
    auto factory = module->getFactory(); factory.setHostContext(&host);
    bool found = false;
    for (const auto& info : factory.classInfos()) {
        if (info.category() == kVstComponentControllerClass) { controllerUid = info.ID(); found = true; }
        if (info.category() == kVstAudioEffectClass) processorUid = info.ID();
    }
    check(found, "controller class missing");
}
int main(int argc, char** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    try {
        check(argc == 3, "usage: editor_host_test bundle good|missing|garbage");
        platformInit();
        loadBundle(argv[1]);
        if (std::string(argv[2]) == "wire") sharedMemoryWire();
        else run(argv[2]);
        module.reset(); platformShutdown(); puts("PASS ALL EDITOR CASES"); return 0;
    } catch (const std::exception& e) { fprintf(stderr, "FAIL %s\n", e.what()); return 1; }
}
