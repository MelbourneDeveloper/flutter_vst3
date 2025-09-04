// Copyright (c) 2025
// Embedded Flutter view for VST3 plugins - Objective-C++ implementation
// Separates FlutterMacOS framework from VST3 headers to avoid conflicts

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>
// TODO: Add FlutterMacOS integration later
// #import <FlutterMacOS/FlutterMacOS.h>
#endif

#include "pluginterfaces/gui/iplugview.h"
#include "base/source/fobject.h"

namespace Steinberg::Vst {

class EmbeddedFlutterView : public IPlugView, public FObject {
public:
    EmbeddedFlutterView() : parentView_(nullptr), flutterViewController_(nullptr) {
        currentSize_.left = 0;
        currentSize_.top = 0;
        currentSize_.right = 600;
        currentSize_.bottom = 420;
    }
    
    virtual ~EmbeddedFlutterView() {
        cleanup();
    }

    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override {
#ifdef __APPLE__
        if (strcmp(type, kPlatformTypeNSView) == 0) return kResultTrue;
#elif defined(_WIN32)
        if (strcmp(type, kPlatformTypeHWND) == 0) return kResultTrue;
#else
        if (strcmp(type, kPlatformTypeX11EmbedWindowID) == 0) return kResultTrue;
#endif
        return kResultFalse;
    }

    tresult PLUGIN_API attached(void* parent, FIDString type) override {
        if (!parent) return kResultFalse;
        
        parentView_ = parent;
        
#ifdef __APPLE__
        NSView* parentNSView = (__bridge NSView*)parent;
        
        // Create a simple test view with dark background and text
        NSView* testView = [[NSView alloc] init];
        testView.wantsLayer = YES;
        testView.layer.backgroundColor = [[NSColor colorWithRed:0.04 green:0.04 blue:0.1 alpha:1.0] CGColor];
        
        // Add a label to show the GUI is working
        NSTextField* label = [[NSTextField alloc] init];
        [label setStringValue:@"Echo Flutter UI (Test Mode)"];
        [label setTextColor:[NSColor whiteColor]];
        [label setBackgroundColor:[NSColor clearColor]];
        [label setBordered:NO];
        [label setSelectable:NO];
        [label setFont:[NSFont systemFontOfSize:18]];
        [label sizeToFit];
        
        // Center the label
        NSRect labelFrame = label.frame;
        labelFrame.origin.x = (600 - labelFrame.size.width) / 2;
        labelFrame.origin.y = (420 - labelFrame.size.height) / 2;
        label.frame = labelFrame;
        
        [testView addSubview:label];
        
        // Configure view size
        testView.frame = NSMakeRect(0, 0, currentSize_.right - currentSize_.left, currentSize_.bottom - currentSize_.top);
        testView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        
        // Add view to parent
        [parentNSView addSubview:testView];
        
        // Store reference to the test view instead of Flutter controller
        flutterViewController_ = testView;
        
#endif
        
        return kResultTrue;
    }

    tresult PLUGIN_API removed() override {
        cleanup();
        return kResultTrue;
    }

    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        *size = currentSize_;
        return kResultTrue;
    }

    tresult PLUGIN_API onSize(ViewRect* newSize) override {
        if (!newSize) return kInvalidArgument;
        currentSize_ = *newSize;
        
#ifdef __APPLE__
        if (flutterViewController_) {
            NSView* testView = (NSView*)flutterViewController_;
            testView.frame = NSMakeRect(0, 0, newSize->right - newSize->left, newSize->bottom - newSize->top);
        }
#endif
        
        return kResultTrue;
    }

    tresult PLUGIN_API setFrame(IPlugFrame* frame) override { return kResultTrue; }
    tresult PLUGIN_API canResize() override { return kResultTrue; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect* rect) override { return kResultTrue; }
    tresult PLUGIN_API onWheel(float distance) override { return kResultTrue; }
    tresult PLUGIN_API onKeyDown(char16 key, int16 keyCode, int16 modifiers) override { return kResultTrue; }
    tresult PLUGIN_API onKeyUp(char16 key, int16 keyCode, int16 modifiers) override { return kResultTrue; }
    tresult PLUGIN_API onFocus(TBool state) override { return kResultTrue; }

    REFCOUNT_METHODS(FObject)
    
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, IPlugView::iid, IPlugView)
        return FObject::queryInterface(iid, obj);
    }

private:
    void cleanup() {
#ifdef __APPLE__
        if (flutterViewController_) {
            NSView* testView = (NSView*)flutterViewController_;
            [testView removeFromSuperview];
            flutterViewController_ = nullptr;
        }
#endif
        parentView_ = nullptr;
    }

    void* parentView_;
    void* flutterViewController_;
    ViewRect currentSize_;
};

// Factory function implementation
IPlugView* createEmbeddedFlutterView() {
    return new EmbeddedFlutterView();
}

} // namespace Steinberg::Vst