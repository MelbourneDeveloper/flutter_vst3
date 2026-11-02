#include <algorithm>
#include <cstdio>
#include <memory>
#include <string>
#include "editor_host_platform.h"
#include "editor_host_recording.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "public.sdk/source/common/memorystream.h"
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
        check(view->attached(window, "unsupported-editor-platform") != kResultTrue, "unsupported platform must not attach");
        platformPump(500);
        check(!platformHasVisibleChild(window), "unsupported platform created a child or pending startup");
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
void interruptedGesture() {
    Editor a; platformPump(1500);
    RecordingHandler handler;
    a.controller->setComponentHandler(&handler);
    auto* controller = dynamic_cast<EditController*>(a.controller.get());
    check(controller != nullptr, "EditController cast");
    controller->beginEdit(0); controller->performEdit(0, 0.37);
    a.view->removed(); handler.exactTriple(0.37);
    controller->endEdit(0); handler.exactTriple(0.37);
    controller->performEdit(0, 0.5); handler.exactTriple(0.37);
    check(a.view->attached(a.window, platformViewType()) == kResultTrue, "gesture reattach");
    platformPump(1500); handler.events.clear();
    controller->beginEdit(0); controller->performEdit(0, 0.61);
    a.view->removed(); handler.exactTriple(0.61);
    a.controller->setComponentHandler(nullptr);
    puts("PASS interrupted gesture and fresh begin after reattach");
}
unsigned long long settledImage(void* window) {
    platformPump(300);
    auto previous = platformCaptureHash(window);
    for (int i = 0; i < 40; ++i) {
        platformPump(100);
        auto current = platformCaptureHash(window);
        if (current == previous) return current;
        previous = current;
    }
    check(false, "parameter image never settled"); return 0;
}
/// Waits for a repaint, since a value reaches the pixels some frames later.
unsigned long long changedImage(void* window, unsigned long long from, const char* failure) {
    for (int i = 0; i < 100; ++i) {
        platformPump(100);
        if (platformCaptureHash(window) != from) return settledImage(window);
    }
    check(false, failure); return 0;
}
void awaitImage(void* window, unsigned long long expected, const char* failure) {
    for (int i = 0; i < 100; ++i) {
        platformPump(100);
        if (platformCaptureHash(window) == expected) return;
    }
    check(false, failure);
}
void displayCycle(Editor& a) {
    a.controller->setParamNormalized(0, 0.5); platformPump(3000);
    auto start = settledImage(a.window);
    a.controller->setParamNormalized(0, 0.1);
    auto low = changedImage(a.window, start, "parameter 0 display unchanged between 0.5 and 0.1");
    a.controller->setParamNormalized(0, 0.9);
    auto high = changedImage(a.window, low, "parameter 0 display unchanged between 0.1 and 0.9");
    MemoryStream state;
    check(a.controller->getState(&state) == kResultTrue, "capture 0.9 state");
    a.controller->setParamNormalized(0, 0.1);
    awaitImage(a.window, low, "parameter 0 display did not return to 0.1");
    state.seek(0, IBStream::kIBSeekSet, nullptr);
    check(a.controller->setComponentState(&state) == kResultTrue, "restore 0.9 state");
    check(a.controller->getParamNormalized(0) == 0.9, "state parameter 0 value");
    awaitImage(a.window, high, "restored state display differs from 0.9");
    a.controller->setParamNormalized(0, 0.1);
    awaitImage(a.window, low, "parameter 0 display did not return to 0.1 after restore");
    a.controller->setParamNormalized(0, 1.0);
    auto top = changedImage(a.window, low, "parameter 0 display unchanged between 0.1 and 1.0");
    a.controller->setParamNormalized(0, 0.1);
    awaitImage(a.window, low, "parameter 0 display did not return to 0.1 from 1.0");
    a.controller->setParamNormalized(0, 1.5);
    check(a.controller->getParamNormalized(0) == 1.0, "out-of-range value not clamped");
    awaitImage(a.window, top, "out-of-range value must display as its clamped value");
}
void reattach(Editor& a) {
    check(a.view->attached(a.window, platformViewType()) == kResultTrue, "reattach");
    platformPump(1500);
}
void displaySync() {
    if (!platformCanCapture()) { puts("NOT RUN display sync: platform cannot capture"); return; }
    Editor a; platformPump(2000);
    for (int cycle = 0; cycle < 2; ++cycle) {
        displayCycle(a); a.view->removed(); reattach(a);
    }
    puts("PASS host to UI display sync and reopen");
}
void pointerCycle(Editor& a, RecordingHandler& handler, bool interrupted) {
    const bool flutter = a.width() == 600;
#if defined(_WIN32)
    constexpr int nativeY = 112;
#else
    constexpr int nativeY = 145;
#endif
    const int x = flutter ? 137 : 82, y = flutter ? 254 : nativeY;
    a.controller->setParamNormalized(0, 0.1); platformPump(500); handler.events.clear();
    platformPress(a.window, x, y);
    platformMove(a.window, flutter ? x : 200, flutter ? y - 25 : y);
    platformMove(a.window, flutter ? x : 350, flutter ? y - 50 : y);
    interrupted ? a.view->removed() : (platformRelease(a.window, x, y), kResultTrue);
    handler.balanced(a.controller->getParamNormalized(0));
    if (interrupted) {
        reattach(a); platformRelease(a.window, x, y);
        handler.balanced(a.controller->getParamNormalized(0));
    }
}
void pointerGesture() {
    if (!platformCanCapture()) { puts("NOT RUN pointer: macOS injection unavailable"); return; }
    Editor a; platformPump(15000); RecordingHandler handler;
    a.controller->setComponentHandler(&handler);
    pointerCycle(a, handler, false); pointerCycle(a, handler, true); pointerCycle(a, handler, false);
    a.controller->setComponentHandler(nullptr); puts("PASS pointer completed and interrupted gestures");
}
void run(const std::string& mode) {
    if (mode != "garbage") displaySync();
    if (mode != "garbage") pointerGesture();
    if (mode != "garbage") interruptedGesture();
    if (mode == "good") {
        { Editor a; platformPump(15000); check(a.width() == 600 && a.child(), "B12/B14 Dart did not start");
          puts("PASS B12/B14 positive"); }
        concurrent(true); concurrent(false); reopenSameView();
        { Editor a; platformPump(500); a.controller->terminate(); a.terminated = true; }
        puts("PASS controller terminate before view close");
        { Editor a; platformPump(3000); rendering(a); }
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
