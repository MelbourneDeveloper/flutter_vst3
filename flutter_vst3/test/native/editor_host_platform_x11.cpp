// Xlib parents and an IRunLoop, pumped the way a Linux host does it.
#include "editor_host_platform.h"
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XTest.h>
#include <poll.h>
#include <unistd.h>
#include <algorithm>
#include <chrono>
#include <vector>
using namespace Steinberg;
using Clock = std::chrono::steady_clock;

namespace {
class Frame : public BasicFrame, public Linux::IRunLoop {
public:
    struct Timer { Linux::ITimerHandler* handler; uint64 interval; Clock::time_point next; };
    struct Event { Linux::IEventHandler* handler; int fd; };
    std::vector<Timer> timers;
    std::vector<Event> events;
    REFCOUNT_METHODS(BasicFrame)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, Linux::IRunLoop::iid, Linux::IRunLoop)
        return BasicFrame::queryInterface(iid, obj);
    }
    tresult PLUGIN_API registerTimer(Linux::ITimerHandler* h, uint64 ms) override {
        timers.push_back({h, ms, Clock::now() + std::chrono::milliseconds(ms)});
        return kResultTrue;
    }
    tresult PLUGIN_API unregisterTimer(Linux::ITimerHandler* h) override {
        timers.erase(std::remove_if(timers.begin(), timers.end(), [h](auto t) { return t.handler == h; }), timers.end());
        return kResultTrue;
    }
    tresult PLUGIN_API registerEventHandler(Linux::IEventHandler* h, int fd) override {
        events.push_back({h, fd});
        return kResultTrue;
    }
    tresult PLUGIN_API unregisterEventHandler(Linux::IEventHandler* h) override {
        events.erase(std::remove_if(events.begin(), events.end(), [h](auto e) { return e.handler == h; }), events.end());
        return kResultTrue;
    }
    void tick() {
        const auto now = Clock::now();
        std::vector<Linux::ITimerHandler*> due;
        for (auto& t : timers) if (now >= t.next) {
            t.next = now + std::chrono::milliseconds(t.interval);
            due.push_back(t.handler);
        }
        for (auto* h : due) h->onTimer();
        for (auto e : events) {
            pollfd p{e.fd, POLLIN, 0};
            if (poll(&p, 1, 0) > 0) e.handler->onFDIsSet(e.fd);
        }
    }
};
Display* display;
Frame frame;
Window asWindow(void* window) { return reinterpret_cast<Window>(window); }
}

void platformInit() {
    display = XOpenDisplay(nullptr);
    check(display != nullptr, "XOpenDisplay");
}
void platformShutdown() { XCloseDisplay(display); }
IPlugFrame* platformFrame() { return &frame; }
const char* platformViewType() { return kPlatformTypeX11EmbedWindowID; }
long long platformProcessId() { return getpid(); }
void* platformCreateWindow() {
    const Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 600, 650, 0, 0, 0);
    XMapWindow(display, window);
    XSync(display, False);
    return reinterpret_cast<void*>(window);
}
void platformDestroyWindow(void* window) {
    XDestroyWindow(display, asWindow(window));
    XSync(display, False);
}
void platformPump(int ms) {
    const auto end = Clock::now() + std::chrono::milliseconds(ms);
    while (Clock::now() < end) {
        frame.tick();
        usleep(1000);
    }
}
bool platformHasVisibleChild(void* window) {
    Window root, parent, *children = nullptr;
    unsigned count = 0;
    bool mapped = false;
    check(XQueryTree(display, asWindow(window), &root, &parent, &children, &count), "XQueryTree");
    for (unsigned i = 0; i < count; ++i) {
        XWindowAttributes a;
        XGetWindowAttributes(display, children[i], &a);
        mapped |= a.map_state == IsViewable;
    }
    if (children) XFree(children);
    return mapped;
}
unsigned long long platformCaptureHash(void* window) {
    XImage* image = XGetImage(display, asWindow(window), 0, 60, 540, 180, AllPlanes, ZPixmap);
    check(image != nullptr, "parameter XGetImage");
    unsigned long long hash = 14695981039346656037ULL;
    for (int y = 0; y < 180; ++y) for (int x = 0; x < 540; ++x) {
        auto pixel = XGetPixel(image, x, y);
        for (int b = 0; b < 4; ++b) { hash ^= (pixel >> (b * 8)) & 255; hash *= 1099511628211ULL; }
    }
    XDestroyImage(image); return hash;
}
void platformMove(void* window, int x, int y) {
    Window child; int sx, sy;
    check(XTranslateCoordinates(display, asWindow(window), DefaultRootWindow(display), x, y, &sx, &sy, &child), "pointer coordinates");
    check(XTestFakeMotionEvent(display, -1, sx, sy, CurrentTime), "XTest motion");
    XFlush(display); platformPump(150);
}
void platformPress(void* window, int x, int y) {
    platformMove(window, x, y);
    check(XTestFakeButtonEvent(display, 1, True, CurrentTime), "XTest press");
    XFlush(display); platformPump(150);
}
void platformRelease(void*, int, int) {
    check(XTestFakeButtonEvent(display, 1, False, CurrentTime), "XTest release");
    XFlush(display); platformPump(150);
}
bool platformCanCapture() { return true; }
bool platformRendered(void* window) {
    XImage* image = XGetImage(display, asWindow(window), 0, 0, 600, 650, AllPlanes, ZPixmap);
    check(image != nullptr, "Rendering: XGetImage failed under Xvfb");
    const auto first = XGetPixel(image, 0, 0);
    bool varied = false;
    for (int y = 0; y < 650; ++y) for (int x = 0; x < 600; ++x)
        varied |= XGetPixel(image, x, y) != first;
    XDestroyImage(image);
    return varied;
}
