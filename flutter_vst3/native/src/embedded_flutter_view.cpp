#include "embedded_flutter_view.h"
#include "base/source/fobject.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "pluginterfaces/base/ustring.h"
#include <string>
#include <algorithm>
#include <vector>
#include <cmath>
#include <memory>
#include <functional>
#include <stdexcept>
#include <optional>
#include <variant>
#include <unordered_map>
#include "vst3_shared_memory.h"
#if defined(__linux__)
#include <dlfcn.h>
#include <sys/stat.h>
#include <gtk/gtk.h>
#include <gtk/gtkx.h>
#if defined(FLUTTER_VST3_HAS_FLUTTER)
#include <flutter_linux/flutter_linux.h>
#endif
#endif

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commctrl.h>
#pragma comment(lib, "comctl32.lib")

#if defined(FLUTTER_VST3_HAS_FLUTTER)
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/binary_messenger.h>
#include <flutter_windows.h>
#include "binary_messenger_impl.h"
#include "vst3_shared_memory.h"
#include <thread>
#include <atomic>
#include <chrono>
#endif
#endif

namespace Steinberg::Vst {

#ifndef __APPLE__

#if defined(_WIN32)
#include "embedded_flutter_view_win_module.inc"
#include "embedded_flutter_view_win_flutter.inc"
#include "embedded_flutter_view_win_native.inc"
#elif defined(__linux__)
#include "embedded_flutter_view_linux_flutter.inc"
#include "embedded_flutter_view_linux_native.inc"
#include "embedded_flutter_view_linux_run_loop.inc"
#endif

/// Cross-platform IPlugView implementation for Windows (HWND) and Linux (X11).
class EmbeddedFlutterView : public IPlugView, public FObject, public IEmbeddedFlutterView {
public:
    EmbeddedFlutterView(EditController* c, const char* name, IEmbeddedFlutterView** holder = nullptr)
        : controller_(c), pluginName_(name ? name : "VST3 Plugin"), viewHolder_(holder) {
#if defined(_WIN32) && defined(FLUTTER_VST3_HAS_FLUTTER)
        hasFlutter_ = WinFlutterHost::checkHasFlutter();
#elif defined(__linux__)
        hasFlutter_ = LinuxFlutterHost::checkHasFlutter();
#endif
        if (viewHolder_) *viewHolder_ = this;
    }

    ~EmbeddedFlutterView() override {
        cleanup();
        if (viewHolder_ && *viewHolder_ == this) *viewHolder_ = nullptr;
    }

    void updateParameter(ParamID paramId, ParamValue value) override {
#if defined(_WIN32)
#if defined(FLUTTER_VST3_HAS_FLUTTER)
        if (hasFlutter_) {
            winFlutterHost_.updateParam(paramId, value);
            return;
        }
#endif
        winHost_.updateParam(paramId, value);
#elif defined(__linux__)
        if (hasFlutter_) {
            linuxFlutterHost_.updateParam(paramId, value);
            return;
        }
        linuxNativeHost_.updateParam(paramId, value);
#endif
    }

    void onControllerClosed() override {
        cleanup();
        controller_ = nullptr;
        viewHolder_ = nullptr;
    }

    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override {
#if defined(_WIN32)
        return (type && strcmp(type, kPlatformTypeHWND) == 0) ? kResultTrue : kResultFalse;
#else
        return (type && strcmp(type, kPlatformTypeX11EmbedWindowID) == 0) ? kResultTrue : kResultFalse;
#endif
    }

    tresult PLUGIN_API attached(void* parent, FIDString type) override {
        if (!parent || !type) return kInvalidArgument;
        parentView_ = parent;
        if (viewHolder_) *viewHolder_ = this;
        size_.reset();
#if defined(_WIN32) && defined(FLUTTER_VST3_HAS_FLUTTER)
        hasFlutter_ = WinFlutterHost::checkHasFlutter();
#elif defined(__linux__)
        hasFlutter_ = LinuxFlutterHost::checkHasFlutter();
#endif
#if defined(_WIN32)
#if defined(FLUTTER_VST3_HAS_FLUTTER)
        winFlutterHost_.onFailure = [this] { mountNativeWindows(); };
        if (hasFlutter_) {
            bool ok = winFlutterHost_.init((HWND)parent, controller_, 600, 650);
            if (!ok) {
                hasFlutter_ = false;
            }
        }
#endif
        if (!hasFlutter_) {
            int count = controller_ ? controller_->getParameterCount() : 0;
            int h = (std::max)(280, 74 + count * 56 + 36);
            if (!winHost_.init((HWND)parent, controller_, pluginName_, 540, h)) return kResultFalse;
        }
#elif defined(__linux__)
        glibPump_.setFrame(frame_);
#if defined(FLUTTER_VST3_HAS_FLUTTER)
        linuxFlutterHost_.onFailure = [this] { mountNativeLinux(); };
#endif
        if (hasFlutter_) {
            bool ok = linuxFlutterHost_.init(parent, controller_, 600, 650);
            if (!ok) {
                hasFlutter_ = false;
            }
        }
        if (!hasFlutter_) {
            int count = controller_ ? controller_->getParameterCount() : 0;
            int h = (std::max)(280, 74 + count * 56 + 36);
            if (!linuxNativeHost_.init(parent, controller_, pluginName_, 540, h)) return kResultFalse;
        }
#endif
        return kResultTrue;
    }

    tresult PLUGIN_API removed() override {
        cleanup();
        if (viewHolder_ && *viewHolder_ == this) *viewHolder_ = nullptr;
        return kResultTrue;
    }

    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        if (size_) { *size = *size_; return kResultTrue; }
        int count = controller_ ? controller_->getParameterCount() : 0;
        size->left = 0;
        size->top = 0;
        size->right = hasFlutter_ ? 600 : 540;
        size->bottom = hasFlutter_ ? 650 : (std::max)(280, 74 + count * 56 + 36);
        return kResultTrue;
    }

    tresult PLUGIN_API onSize(ViewRect* r) override {
        if (!r || r->getWidth() <= 0 || r->getHeight() <= 0) return kInvalidArgument;
        size_ = *r;
#if defined(_WIN32)
        if (r) {
#if defined(FLUTTER_VST3_HAS_FLUTTER)
            if (hasFlutter_ && winFlutterHost_.flutterHwnd) {
                SetWindowPos(winFlutterHost_.flutterHwnd, nullptr, 0, 0, r->getWidth(), r->getHeight(), SWP_NOMOVE | SWP_NOZORDER);
                return kResultTrue;
            }
#endif
            if (winHost_.hwnd) {
                SetWindowPos(winHost_.hwnd, nullptr, 0, 0, r->getWidth(), r->getHeight(), SWP_NOMOVE | SWP_NOZORDER);
            }
        }
#elif defined(__linux__)
        if (!r) return kInvalidArgument;
        auto* plug = hasFlutter_ ? linuxFlutterHost_.plug : linuxNativeHost_.plug;
        if (plug) gtk_widget_set_size_request(plug, r->getWidth(), r->getHeight());
#endif
        return kResultTrue;
    }

    tresult PLUGIN_API setFrame(IPlugFrame* frame) override {
        frame_ = frame;
#if defined(__linux__)
        glibPump_.setFrame(frame);
#endif
        return kResultTrue;
    }
    tresult PLUGIN_API canResize() override { return kResultTrue; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect*) override { return kResultTrue; }
    tresult PLUGIN_API onWheel(float) override { return kResultFalse; }
    tresult PLUGIN_API onKeyDown(char16, int16, int16) override { return kResultFalse; }
    tresult PLUGIN_API onKeyUp(char16, int16, int16) override { return kResultFalse; }
    tresult PLUGIN_API onFocus(TBool) override { return kResultTrue; }

    REFCOUNT_METHODS(FObject)

    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, IPlugView::iid, IPlugView)
        return FObject::queryInterface(iid, obj);
    }

private:
#if defined(_WIN32) && defined(FLUTTER_VST3_HAS_FLUTTER)
    void mountNativeWindows() {
        hasFlutter_ = false;
        size_.reset();
        const int count = controller_ ? controller_->getParameterCount() : 0;
        const int height = (std::max)(280, 74 + count * 56 + 36);
        if (!winHost_.init((HWND)parentView_, controller_, pluginName_, 540, height))
            throw std::runtime_error("Native Windows editor failed after Flutter startup failure");
        ViewRect rect(0, 0, 540, height);
        if (frame_) frame_->resizeView(this, &rect);
    }
#endif
#if defined(__linux__)
    void mountNativeLinux() {
        hasFlutter_ = false;
        size_.reset();
        const int count = controller_ ? controller_->getParameterCount() : 0;
        const int height = (std::max)(280, 74 + count * 56 + 36);
        if (!linuxNativeHost_.init(parentView_, controller_, pluginName_, 540, height))
            throw std::runtime_error("Native Linux editor failed after Flutter startup failure");
        ViewRect rect(0, 0, 540, height);
        if (frame_) frame_->resizeView(this, &rect);
    }
#endif
    void cleanup() {
#if defined(_WIN32)
#if defined(FLUTTER_VST3_HAS_FLUTTER)
        if (hasFlutter_) {
            winFlutterHost_.shutdown();
        }
#endif
        winHost_.shutdown();
#elif defined(__linux__)
        glibPump_.stop();
        if (hasFlutter_) {
            linuxFlutterHost_.shutdown();
        }
        linuxNativeHost_.shutdown();
#endif
        parentView_ = nullptr;
        hasFlutter_ = false;
        size_.reset();
    }

    std::optional<ViewRect> size_;
    IPlugFrame* frame_{nullptr};
    EditController* controller_{nullptr};
    std::string pluginName_;
    void* parentView_{nullptr};
    IEmbeddedFlutterView** viewHolder_{nullptr};
    bool hasFlutter_{false};
#if defined(_WIN32)
#if defined(FLUTTER_VST3_HAS_FLUTTER)
    WinFlutterHost winFlutterHost_;
#endif
    WinNativeEditorHost winHost_;
#elif defined(__linux__)
    LinuxGlibPump glibPump_;
    LinuxFlutterHost linuxFlutterHost_;
    LinuxNativeEditorHost linuxNativeHost_;
#endif
};

IPlugView* createEmbeddedFlutterView(
    EditController* controller,
    const char* pluginName,
    IEmbeddedFlutterView** outViewPtr) {
    return new EmbeddedFlutterView(controller, pluginName, outViewPtr);
}

#endif // !__APPLE__

} // namespace Steinberg::Vst