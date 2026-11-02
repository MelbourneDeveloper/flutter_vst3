// Cocoa parents and a main run loop.
#include "editor_host_platform.h"
#import <Cocoa/Cocoa.h>
#include <unistd.h>
using namespace Steinberg;

namespace {
BasicFrame frame;
NSView* asView(void* window) { return (__bridge NSView*)window; }
}

void platformInit() {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
}
void platformShutdown() {}
IPlugFrame* platformFrame() { return &frame; }
const char* platformViewType() { return kPlatformTypeNSView; }
long long platformProcessId() { return getpid(); }
void* platformCreateWindow() {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 650)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    [window orderFrontRegardless];
    return (__bridge_retained void*)window.contentView;
}
void platformDestroyWindow(void* window) {
    NSView* view = (__bridge_transfer NSView*)window;
    [view.window orderOut:nil];
}
void platformPump(int ms) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:ms / 1000.0];
    while ([end timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
    }
}
bool platformHasVisibleChild(void* window) {
    for (NSView* child in asView(window).subviews) {
        if (!child.isHidden) return true;
    }
    return false;
}
// Reading a Metal layer back needs a screen recording permission that CI lacks.
void queueMouse(void* window, int x, int y, NSEventType type) {
    NSView* view = asView(window);
    NSPoint point = [view convertPoint:NSMakePoint(x, view.bounds.size.height - y) toView:nil];
    NSEvent* event = [NSEvent mouseEventWithType:type location:point modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber
        context:nil eventNumber:0 clickCount:1 pressure:type == NSEventTypeLeftMouseUp ? 0 : 1];
    [NSApp postEvent:event atStart:NO];
}
void platformPress(void* w, int x, int y) { queueMouse(w, x, y, NSEventTypeLeftMouseDown); }
void platformMove(void* w, int x, int y) { queueMouse(w, x, y, NSEventTypeLeftMouseDragged); }
void platformRelease(void* w, int x, int y) {
    queueMouse(w, x, y, NSEventTypeLeftMouseUp); platformPump(500);
}
unsigned long long platformCaptureHash(void* window) {
    NSView* view = asView(window);
    NSBitmapImageRep* bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    check(bitmap != nil, "H14 native bitmap allocation");
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    unsigned long long hash = 1469598103934665603ULL;
    for (NSInteger i = 0; i < bitmap.bytesPerRow * bitmap.pixelsHigh; ++i)
        hash = (hash ^ bitmap.bitmapData[i]) * 1099511628211ULL;
    return hash;
}
bool platformCanCapture() { return false; }
bool platformRendered(void*) {
    throw std::runtime_error("Rendering cannot be captured on macOS");
}
