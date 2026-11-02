// Copyright (c) 2025
// Native embedded view for flutter_vst3 plugins on macOS
// Hosts an in-process Flutter Engine with dynamic fallback to Cocoa UI.

#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <objc/message.h>
#include "embedded_flutter_view.h"
#include "native_cocoa_view.h"
#include "vst3_shared_memory.h"
#include "base/source/fobject.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include <string>
#include <memory>
#include <atomic>
#include <optional>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

namespace Steinberg::Vst {

/// Locates the VST3 bundle directory for the current dylib.
static NSString* findPluginBundlePath() {
    Dl_info info;
    if (!dladdr((const void*)&createEmbeddedFlutterView, &info) || !info.dli_fname) return nil;
    auto dylibPath = [NSString stringWithUTF8String:info.dli_fname];
    auto macosDir = [dylibPath stringByDeletingLastPathComponent];
    auto contentsDir = [macosDir stringByDeletingLastPathComponent];
    auto bundleDir = [contentsDir stringByDeletingLastPathComponent];
    return [[bundleDir pathExtension] isEqualToString:@"vst3"] ? bundleDir : contentsDir;
}

/// Checks if the bundle contains an embedded Flutter App.framework.
static BOOL pluginHasFlutter(NSString* bundlePath) {
#ifndef VST3_FLUTTER_ENTRYPOINT
    return NO;
#else
    if (!bundlePath) return NO;
    auto fm = [NSFileManager defaultManager];
    auto fwDir = [bundlePath stringByAppendingPathComponent:@"Contents/Frameworks"];
    return [fm fileExistsAtPath:[fwDir stringByAppendingPathComponent:@"App.framework/App"]]
        && [fm fileExistsAtPath:[fwDir stringByAppendingPathComponent:@"App.framework/Resources/flutter_assets"]]
        && [fm fileExistsAtPath:[fwDir stringByAppendingPathComponent:@"FlutterMacOS.framework/Resources/icudtl.dat"]];
#endif
}

/// Dynamically loads Flutter and App frameworks from the bundle.
static BOOL loadFlutterFrameworks(NSString* bundlePath, NSBundle** outFlutter, NSBundle** outApp) {
    if (!bundlePath) return NO;
    auto fm = [NSFileManager defaultManager];
    auto fwDir = [bundlePath stringByAppendingPathComponent:@"Contents/Frameworks"];
    auto flPath = [fwDir stringByAppendingPathComponent:@"FlutterMacOS.framework"];
    auto appPath = [fwDir stringByAppendingPathComponent:@"App.framework"];
    if (![fm fileExistsAtPath:flPath] || ![fm fileExistsAtPath:appPath]) return NO;
    *outFlutter = [NSBundle bundleWithPath:flPath];
    *outApp = [NSBundle bundleWithPath:appPath];
    if (!NSClassFromString(@"FlutterViewController")) {
        if (![*outFlutter load]) return NO;
    }
    return YES;
}

/// The engine crashes the host when the app library is corrupt, so try it first.
static BOOL appLibraryLoads(NSBundle* appBundle) {
    void* handle = dlopen(appBundle.executablePath.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        NSLog(@"[flutter_vst3] Flutter app library failed to load: %s", dlerror());
        return NO;
    }
    dlclose(handle);
    return YES;
}

/// Native macOS IPlugView embedding Flutter or falling back to Cocoa sliders.
class EmbeddedFlutterView : public Steinberg::IPlugView,
                            public Steinberg::FObject,
                            public IEmbeddedFlutterView {
public:
    EmbeddedFlutterView(EditController* c, const char* name, IEmbeddedFlutterView** holder = nullptr)
        : controller_(c), pluginName_(name ? name : "VST3 Plugin"), viewHolder_(holder) {
        hasFlutter_ = pluginHasFlutter(findPluginBundlePath());
        if (viewHolder_) *viewHolder_ = this;
    }

    ~EmbeddedFlutterView() override {
        cleanup();
        if (viewHolder_ && *viewHolder_ == this) *viewHolder_ = nullptr;
    }

    void onControllerClosed() override {
        cleanup();
        controller_ = nullptr;
        if (cocoaDelegate_) cocoaDelegate_.controller = nullptr;
        viewHolder_ = nullptr;
    }

    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override {
        return (type && strcmp(type, kPlatformTypeNSView) == 0) ? kResultTrue : kResultFalse;
    }

    tresult PLUGIN_API attached(void* parent, FIDString type) override {
        if (!parent || !type || strcmp(type, kPlatformTypeNSView) != 0) return kInvalidArgument;
        parentView_ = parent;
        size_.reset();
        hasFlutter_ = !sOwner && pluginHasFlutter(findPluginBundlePath());
        if (hasFlutter_) sOwner = this;
        NSView* parentNsView = (__bridge NSView*)parent;
        alive_ = std::make_shared<std::atomic<bool>>(true);
        auto alive = alive_;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (alive->load() && parentView_ == parent) {
                mountView(parentNsView);
            }
        });
        return kResultTrue;
    }

    tresult PLUGIN_API removed() override {
        endControllerEdits(controller_);
        cleanup();
        if (viewHolder_ && *viewHolder_ == this) *viewHolder_ = nullptr;
        return kResultTrue;
    }

    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        if (size_) { *size = *size_; return kResultTrue; }
        size->left = 0;
        size->top = 0;
        size->right = hasFlutter_ ? 600 : 540;
        int count = controller_ ? controller_->getParameterCount() : 0;
        size->bottom = hasFlutter_ ? 650 : std::max(280, 74 + count * 56 + 36);
        return kResultTrue;
    }

    tresult PLUGIN_API onSize(ViewRect* rect) override {
        if (!rect || rect->getWidth() <= 0 || rect->getHeight() <= 0) return kInvalidArgument;
        size_ = *rect;
        NSView* view = flutterViewController_
            ? [flutterViewController_ performSelector:sel_registerName("view")] : cocoaContainerView_;
        [view setFrameSize:NSMakeSize(rect->getWidth(), rect->getHeight())];
        return kResultTrue;
    }
    tresult PLUGIN_API setFrame(IPlugFrame* frame) override { frame_ = frame; return kResultTrue; }
    tresult PLUGIN_API canResize() override { return kResultTrue; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect*) override { return kResultTrue; }
    tresult PLUGIN_API onWheel(float) override { return kResultFalse; }
    tresult PLUGIN_API onKeyDown(char16, int16, int16) override { return kResultFalse; }
    tresult PLUGIN_API onKeyUp(char16, int16, int16) override { return kResultFalse; }
    tresult PLUGIN_API onFocus(TBool) override { return kResultTrue; }

    void updateParameter(ParamID paramId, ParamValue value) override {
        auto alive = alive_;
        id flChannel = flutterChannel_;
        if (flChannel) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!alive->load()) return;
                NSDictionary* args = @{@"id": @(paramId), @"value": @(value)};
                [flChannel performSelector:sel_registerName("invokeMethod:arguments:")
                                withObject:@"onParameterChanged"
                                withObject:args];
            });
        } else if (cocoaDelegate_) {
            auto del = cocoaDelegate_;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (alive->load()) [del updateParamId:paramId withValue:value];
            });
        }
    }

    REFCOUNT_METHODS(Steinberg::FObject)

    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, Steinberg::IPlugView::iid, Steinberg::IPlugView)
        return Steinberg::FObject::queryInterface(iid, obj);
    }

private:
    void cleanup() {
        alive_->store(false);
        if (cocoaDelegate_) cocoaDelegate_.controller = nullptr;
        if (flutterChannel_) {
            [flutterChannel_ performSelector:sel_registerName("setMethodCallHandler:") withObject:nil];
            flutterChannel_ = nil;
        }
        if (flutterViewController_) {
            id engine = [flutterViewController_ performSelector:sel_registerName("engine")];
            NSView* v = [flutterViewController_ performSelector:sel_registerName("view")];
            [v removeFromSuperview];
            if (engine) {
                ((void (*)(id, SEL))objc_msgSend)(engine, sel_registerName("shutDownEngine"));
            }
            flutterViewController_ = nil;
        }
        if (cocoaContainerView_) {
            [cocoaContainerView_ removeFromSuperview];
            cocoaContainerView_ = nil;
            cocoaDelegate_ = nil;
        }
        if (sOwner == this) sOwner = nullptr;
        hasFlutter_ = NO;
        size_.reset();
        parentView_ = nullptr;
    }

    void mountView(NSView* parent) {
        BOOL mounted = NO;
        if (hasFlutter_) {
            @try {
                mounted = tryMountFlutter(parent);
            } @catch (NSException* e) {
                NSLog(@"[flutter_vst3] Flutter UI mount exception: %@. Falling back to Cocoa.", e);
                mounted = NO;
            }
        }
        if (!mounted) {
            hasFlutter_ = NO;
            size_.reset();
            if (sOwner == this) sOwner = nullptr;
            Vst3PluginEditorDelegate* del = nil;
            cocoaContainerView_ = createCocoaFallbackView(parent, controller_, pluginName_, &del);
            cocoaDelegate_ = del;
            [parent addSubview:cocoaContainerView_];
        }
    }

    BOOL tryMountFlutter(NSView* parent) {
        NSBundle *flBundle = nil, *appBundle = nil;
        if (!loadFlutterFrameworks(findPluginBundlePath(), &flBundle, &appBundle)) return NO;
        if (!appLibraryLoads(appBundle)) return NO;
        Class projCls = NSClassFromString(@"FlutterDartProject");
        Class vcCls = NSClassFromString(@"FlutterViewController");
        if (!projCls || !vcCls) return NO;

        id proj = [[projCls alloc] performSelector:sel_registerName("initWithPrecompiledDartBundle:") withObject:appBundle];
        flutterViewController_ = [[vcCls alloc] performSelector:sel_registerName("initWithProject:") withObject:proj];
        if (!flutterViewController_) return NO;

        setupMethodChannel();
        NSView* fv = [flutterViewController_ performSelector:sel_registerName("view")];
        NSRect b = parent.bounds;
        if (b.size.width <= 0 || b.size.height <= 0) b = NSMakeRect(0, 0, 600, 650);
        [fv setFrame:b];
        [fv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [parent addSubview:fv];

        id engine = [flutterViewController_ performSelector:sel_registerName("engine")];
        BOOL isRunning = engine
            ? ((BOOL (*)(id, SEL))objc_msgSend)(engine, sel_registerName("running"))
            : NO;
        if (!isRunning && [flutterViewController_ respondsToSelector:sel_registerName("launchEngine")]) {
            isRunning = ((BOOL (*)(id, SEL))objc_msgSend)(
                flutterViewController_, sel_registerName("launchEngine"));
        }
        if (!isRunning) {
            NSLog(@"[flutter_vst3] FlutterEngine failed to launch (e.g. Dart SDK hash mismatch). Falling back to Cocoa.");
            [fv removeFromSuperview];
            if (flutterChannel_) {
                [flutterChannel_ performSelector:sel_registerName("setMethodCallHandler:") withObject:nil];
                flutterChannel_ = nil;
            }
            if (engine) ((void (*)(id, SEL))objc_msgSend)(engine, sel_registerName("shutDownEngine"));
            flutterViewController_ = nil;
            return NO;
        }
        return YES;
    }

    void setupMethodChannel() {
        id engine = [flutterViewController_ performSelector:sel_registerName("engine")];
        id messenger = [engine performSelector:sel_registerName("binaryMessenger")];
        Class chanCls = NSClassFromString(@"FlutterMethodChannel");
        flutterChannel_ = [chanCls performSelector:sel_registerName("methodChannelWithName:binaryMessenger:")
                                        withObject:@"flutter_vst3/parameters"
                                        withObject:messenger];
        auto alive = alive_;
        id flHandler = ^(id call, void (^result)(id)) {
            if (!alive->load()) { result(nil); return; }
            handleMethodCall(call, result, controller_);
        };
        [flutterChannel_ performSelector:sel_registerName("setMethodCallHandler:") withObject:flHandler];
    }

    static void handleSetParameter(NSDictionary* args, EditController* ctrl, void (^result)(id)) {
        int pid = [args[@"id"] intValue];
        double val = [args[@"value"] doubleValue];
        ctrl->setParamNormalized(pid, val);
        ctrl->performEdit(pid, val);
        result(@(YES));
    }

    static void handleGetInitialParameters(EditController* ctrl, void (^result)(id)) {
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        if (ctrl) {
            int count = ctrl->getParameterCount();
            for (int i = 0; i < count; ++i) {
                ParameterInfo info;
                if (ctrl->getParameterInfo(i, info) == kResultTrue) {
                    dict[@(info.id)] = @(ctrl->getParamNormalized(info.id));
                }
            }
        }
        result(dict);
    }

    static void handleGetSharedMemoryInfo(EditController* ctrl, void (^result)(id)) {
        uintptr_t addr = controllerShmAddress(ctrl);
        result(@{
            @"address": @(addr),
            @"totalSize": @(VST3_SHM_TOTAL_SIZE),
            @"maxSamples": @(VST3_SHM_MAX_SAMPLES)
        });
    }

    static void handleMethodCall(id call, void (^result)(id), EditController* ctrl) {
        NSString* method = [call performSelector:sel_registerName("method")];
        id arguments = [call performSelector:sel_registerName("arguments")];
        if (([method isEqualToString:@"beginEdit"] || [method isEqualToString:@"endEdit"]) && ctrl) {
            const auto pid = [arguments[@"id"] unsignedIntValue];
            [method isEqualToString:@"beginEdit"] ? ctrl->beginEdit(pid) : ctrl->endEdit(pid);
            result(@(YES));
        } else if ([method isEqualToString:@"setParameter"] && ctrl) {
            handleSetParameter((NSDictionary*)arguments, ctrl, result);
        } else if ([method isEqualToString:@"getInitialParameters"] && ctrl) {
            handleGetInitialParameters(ctrl, result);
        } else if ([method isEqualToString:@"getSharedMemoryInfo"]) {
            handleGetSharedMemoryInfo(ctrl, result);
        } else {
            result(nil);
        }
    }

    std::shared_ptr<std::atomic<bool>> alive_{std::make_shared<std::atomic<bool>>(true)};
    std::optional<ViewRect> size_;
    EditController* controller_{nullptr};
    std::string pluginName_;
    void* parentView_{nullptr};
    IPlugFrame* frame_{nullptr};
    IEmbeddedFlutterView** viewHolder_{nullptr};
    static inline EmbeddedFlutterView* sOwner{nullptr};
    BOOL hasFlutter_{NO};
    id flutterViewController_{nil};
    id flutterChannel_{nil};
    NSView* cocoaContainerView_{nil};
    Vst3PluginEditorDelegate* cocoaDelegate_{nil};
};

Steinberg::IPlugView* createEmbeddedFlutterView(
    EditController* controller,
    const char* pluginName,
    IEmbeddedFlutterView** outViewPtr) {
    return new EmbeddedFlutterView(controller, pluginName, outViewPtr);
}

} // namespace Steinberg::Vst

#pragma clang diagnostic pop