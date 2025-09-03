// Copyright (c) 2025
//
// Minimal view implementation that launches an external Flutter UI
// application. This plug‑in uses an external window to avoid
// embedding Flutter directly into the VST host for now. When the
// view is attached, the external process is started; when removed it
// simply retains its state. Resize support is limited.

#include "public.sdk/source/vst/utility/uid.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include <thread>
#include <atomic>
#include <string>
#include <unistd.h>
#include <sys/wait.h>

#if defined(_WIN32)
#include <windows.h>
#endif

namespace Steinberg::Vst {

class DummyView : public IPlugView, public FObject {
public:
  DummyView() {}
  ~DummyView() override {}

  tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override {
#if defined(_WIN32)
    if (strcmp(type, kPlatformTypeHWND) == 0) return kResultTrue;
#elif defined(__APPLE__)
    if (strcmp(type, kPlatformTypeNSView) == 0) return kResultTrue;
#else
    if (strcmp(type, kPlatformTypeX11EmbedWindowID) == 0) return kResultTrue;
#endif
    return kInvalidArgument;
  }

  tresult PLUGIN_API attached(void* parent, FIDString) override {
    parent_ = parent;
    launchFlutter();
    return kResultTrue;
  }
  tresult PLUGIN_API removed() override {
    parent_ = nullptr;
    return kResultTrue;
  }
  tresult PLUGIN_API onSize(ViewRect*) override { return kResultTrue; }
  tresult PLUGIN_API getSize(ViewRect* r) override {
    if (!r) return kInvalidArgument;
    r->left = 0;
    r->top = 0;
    r->right = 600;
    r->bottom = 420;
    return kResultTrue;
  }
  tresult PLUGIN_API setFrame(IPlugFrame*) override { return kResultTrue; }
  tresult PLUGIN_API canResize() override { return kResultTrue; }
  tresult PLUGIN_API checkSizeConstraint(ViewRect*) override { return kResultTrue; }

  REFCOUNT_METHODS(FObject)
  tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
    QUERY_INTERFACE(iid, obj, IPlugView::iid, IPlugView)
    return FObject::queryInterface(iid, obj);
  }

private:
  void* parent_{nullptr};
  std::atomic<bool> launched_{false};

  void launchFlutter() {
    if (launched_.exchange(true)) return;
#if defined(_WIN32)
    std::wstring exe = L"flutter_ui\\build\\windows\\runner\\Release\\flutter_ui.exe";
    STARTUPINFO si{};
    PROCESS_INFORMATION pi{};
    CreateProcessW(exe.c_str(), NULL, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
#elif defined(__APPLE__)
    system("open flutter_ui/build/macos/Build/Products/Release/flutter_ui.app");
#else
    if (!fork()) {
      execl("flutter_ui/build/linux/x64/release/bundle/flutter_ui", "flutter_ui", (char*)NULL);
      _exit(0);
    }
#endif
  }
};

} // namespace Steinberg::Vst