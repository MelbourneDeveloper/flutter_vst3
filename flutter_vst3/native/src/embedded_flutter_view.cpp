#include "embedded_flutter_view.h"
#include "base/source/fobject.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "pluginterfaces/base/ustring.h"
#include <string>
#include <algorithm>
#include <vector>
#include <cmath>
#include <memory>
#include <variant>
#include <unordered_map>
#include "vst3_shared_memory.h"

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
#include <mutex>
#endif
#endif

namespace Steinberg::Vst {

#ifndef __APPLE__

#if defined(_WIN32)

#if defined(FLUTTER_VST3_HAS_FLUTTER)
class WinFlutterHost {
public:
    HWND flutterHwnd{nullptr};
    HWND parentHwnd{nullptr};
    EditController* controller{nullptr};
    int width{600};
    int height{650};

    UINT_PTR pendingTimerId{0};
    std::atomic<bool> mounted{false};

    static inline HWND sSharedFlutterHwnd{nullptr};
    static inline FlutterDesktopViewControllerRef sSharedVc{nullptr};
    static inline FlutterDesktopEngineRef sSharedEngine{nullptr};
    static inline std::unique_ptr<flutter::BinaryMessengerImpl> sSharedMessenger;
    static inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> sSharedChannel;
    static inline HMODULE sFlDll{nullptr};
    static inline EditController* sActiveController{nullptr};
    static inline std::mutex sSharedMutex;

    static HWND getHolderHwnd() {
        static HWND holder = nullptr;
        if (!holder) {
            HINSTANCE hInst = GetModuleHandleW(nullptr);
            WNDCLASSEXW wc{};
            wc.cbSize = sizeof(WNDCLASSEXW);
            wc.lpfnWndProc = DefWindowProcW;
            wc.hInstance = hInst;
            wc.lpszClassName = L"FlutterVst3HolderWindow";
            RegisterClassExW(&wc);

            holder = CreateWindowExW(
                0, L"FlutterVst3HolderWindow", L"FlutterHolder",
                WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, hInst, nullptr
            );
        }
        return holder;
    }

    static std::wstring getModuleDirectory() {
        HMODULE hModule = nullptr;
        GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&createEmbeddedFlutterView),
            &hModule);
        wchar_t path[MAX_PATH];
        GetModuleFileNameW(hModule, path, MAX_PATH);
        std::wstring p(path);
        size_t lastSlash = p.find_last_of(L"\\/");
        if (lastSlash != std::wstring::npos) {
            return p.substr(0, lastSlash);
        }
        return L"";
    }

    static bool checkHasFlutter() {
        std::wstring moduleDir = getModuleDirectory();
        if (moduleDir.empty()) return false;
        std::wstring assetsPath = moduleDir + L"\\data\\flutter_assets";
        DWORD attr = GetFileAttributesW(assetsPath.c_str());
        return (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY));
    }

    bool init(HWND parent, EditController* ctrl, int w, int h) {
        controller = ctrl;
        sActiveController = ctrl;
        parentHwnd = parent;
        width = w;
        height = h;
        mounted = false;

        std::wstring moduleDir = getModuleDirectory();
        if (moduleDir.empty()) return false;

        std::wstring dllPath = moduleDir + L"\\flutter_windows.dll";
        std::wstring assetsPath = moduleDir + L"\\data\\flutter_assets";
        DWORD attr = GetFileAttributesW(assetsPath.c_str());
        if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
            return false;
        }

        if (!sFlDll) {
            SetDllDirectoryW(moduleDir.c_str());
            sFlDll = LoadLibraryW(dllPath.c_str());
            if (!sFlDll) return false;
        }

        // Post-mount via thread timer so it executes on the main platform thread
        // AFTER the Dart FFI call (openEditorWindow) has returned to the event loop.
        UINT_PTR tid = SetTimer(nullptr, 0, 10, &WinFlutterHost::timerProc);
        if (tid == 0) return false;
        pendingTimerId = tid;
        registerTimer(tid, this);
        return true;
    }

    void mount() {
        if (mounted.load() || !parentHwnd) return;
        mounted = true;

        std::lock_guard<std::mutex> lock(sSharedMutex);

        if (!sSharedVc) {
            std::wstring moduleDir = getModuleDirectory();
            std::wstring assetsPath = moduleDir + L"\\data\\flutter_assets";
            std::wstring icuPath = moduleDir + L"\\data\\icudtl.dat";

            FlutterDesktopEngineProperties props{};
            props.assets_path = assetsPath.c_str();
            props.icu_data_path = icuPath.c_str();
            props.dart_entrypoint = "echoMain";
            props.ui_thread_policy = RunOnPlatformThread;
            props.impeller_switch = DisabledImpeller;

            sSharedEngine = FlutterDesktopEngineCreate(&props);
            if (!sSharedEngine) {
                mounted = false;
                return;
            }

            setupMethodChannel();

            if (!FlutterDesktopEngineRun(sSharedEngine, "echoMain")) {
                FlutterDesktopEngineDestroy(sSharedEngine);
                sSharedEngine = nullptr;
                mounted = false;
                return;
            }

            sSharedVc = FlutterDesktopViewControllerCreate(width, height, sSharedEngine);
            if (!sSharedVc) {
                sSharedEngine = nullptr;
                mounted = false;
                return;
            }

            FlutterDesktopViewRef view = FlutterDesktopViewControllerGetView(sSharedVc);
            if (!view) {
                FlutterDesktopViewControllerDestroy(sSharedVc);
                sSharedVc = nullptr;
                sSharedEngine = nullptr;
                mounted = false;
                return;
            }

            sSharedFlutterHwnd = FlutterDesktopViewGetHWND(view);
            if (!sSharedFlutterHwnd) {
                FlutterDesktopViewControllerDestroy(sSharedVc);
                sSharedVc = nullptr;
                sSharedEngine = nullptr;
                mounted = false;
                return;
            }

            LONG_PTR curStyle = GetWindowLongPtrW(sSharedFlutterHwnd, GWL_STYLE);
            curStyle = (curStyle & ~WS_POPUP) | WS_CHILD;
            SetWindowLongPtrW(sSharedFlutterHwnd, GWL_STYLE, curStyle);
        }

        RECT rc{};
        GetClientRect(parentHwnd, &rc);
        int w = rc.right - rc.left;
        int h = rc.bottom - rc.top;
        if (w <= 0) w = width > 0 ? width : 600;
        if (h <= 0) h = height > 0 ? height : 650;

        flutterHwnd = sSharedFlutterHwnd;
        SetParent(sSharedFlutterHwnd, parentHwnd);
        SetWindowPos(sSharedFlutterHwnd, nullptr, 0, 0, w, h, SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        ShowWindow(sSharedFlutterHwnd, SW_SHOW);
        UpdateWindow(sSharedFlutterHwnd);
        FlutterDesktopViewControllerForceRedraw(sSharedVc);

        // Notify Flutter UI and synchronize parameters (mirroring Linux)
        if (sSharedChannel) {
            sSharedChannel->InvokeMethod("onHostAttached", nullptr);
            if (sActiveController) {
                int count = sActiveController->getParameterCount();
                for (int i = 0; i < count; ++i) {
                    Steinberg::Vst::ParameterInfo info{};
                    if (sActiveController->getParameterInfo(i, info) == Steinberg::kResultTrue) {
                        updateParam(info.id, sActiveController->getParamNormalized(info.id));
                    }
                }
            }
        }
    }

    void shutdown() {
        if (pendingTimerId != 0) {
            KillTimer(nullptr, pendingTimerId);
            unregisterTimer(pendingTimerId);
            pendingTimerId = 0;
        }

        std::lock_guard<std::mutex> lock(sSharedMutex);

        if (sSharedChannel) {
            sSharedChannel->InvokeMethod("onHostDetached", nullptr);
        }

        if (sSharedFlutterHwnd) {
            ShowWindow(sSharedFlutterHwnd, SW_HIDE);
            SetParent(sSharedFlutterHwnd, getHolderHwnd());
        }

        if (sActiveController == controller) {
            sActiveController = nullptr;
        }

        flutterHwnd = nullptr;
        parentHwnd = nullptr;
        mounted = false;
    }

    void updateParam(Steinberg::Vst::ParamID pid, Steinberg::Vst::ParamValue val) {
        std::lock_guard<std::mutex> lock(sSharedMutex);
        if (!sSharedChannel) return;
        flutter::EncodableMap args;
        args[flutter::EncodableValue("id")] = flutter::EncodableValue(static_cast<int64_t>(pid));
        args[flutter::EncodableValue("value")] = flutter::EncodableValue(static_cast<double>(val));
        sSharedChannel->InvokeMethod("onParameterChanged", std::make_unique<flutter::EncodableValue>(args));
    }

private:
    void setupMethodChannel() {
        FlutterDesktopMessengerRef messenger = FlutterDesktopEngineGetMessenger(sSharedEngine);
        if (!messenger) return;

        sSharedMessenger = std::make_unique<flutter::BinaryMessengerImpl>(messenger);
        sSharedChannel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            sSharedMessenger.get(), "flutter_vst3/parameters",
            &flutter::StandardMethodCodec::GetInstance());

        sSharedChannel->SetMethodCallHandler(
            [](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
                auto* ctrl = sActiveController;
                if (call.method_name() == "setParameter" && ctrl) {
                    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                    if (!args) {
                        result->Error("INVALID_ARGUMENTS", "Expected map arguments");
                        return;
                    }
                    auto idIt = args->find(flutter::EncodableValue("id"));
                    auto valIt = args->find(flutter::EncodableValue("value"));
                    if (idIt != args->end() && valIt != args->end()) {
                        int pid = 0;
                        if (std::holds_alternative<int32_t>(idIt->second)) {
                            pid = std::get<int32_t>(idIt->second);
                        } else if (std::holds_alternative<int64_t>(idIt->second)) {
                            pid = static_cast<int>(std::get<int64_t>(idIt->second));
                        }
                        double val = 0.0;
                        if (std::holds_alternative<double>(valIt->second)) {
                            val = std::get<double>(valIt->second);
                        } else if (std::holds_alternative<int32_t>(valIt->second)) {
                            val = static_cast<double>(std::get<int32_t>(valIt->second));
                        } else if (std::holds_alternative<int64_t>(valIt->second)) {
                            val = static_cast<double>(std::get<int64_t>(valIt->second));
                        }
                        ctrl->beginEdit(pid);
                        ctrl->setParamNormalized(pid, val);
                        ctrl->performEdit(pid, val);
                        ctrl->endEdit(pid);
                        result->Success(flutter::EncodableValue(true));
                    } else {
                        result->Error("MISSING_PARAM", "id or value missing");
                    }
                } else if (call.method_name() == "getInitialParameters") {
                    flutter::EncodableMap map;
                    if (ctrl) {
                        int count = ctrl->getParameterCount();
                        for (int i = 0; i < count; ++i) {
                            Steinberg::Vst::ParameterInfo info{};
                            if (ctrl->getParameterInfo(i, info) == Steinberg::kResultTrue) {
                                map[flutter::EncodableValue(static_cast<int64_t>(info.id))] =
                                    flutter::EncodableValue(ctrl->getParamNormalized(info.id));
                            }
                        }
                    }
                    result->Success(flutter::EncodableValue(map));
                } else if (call.method_name() == "getSharedMemoryInfo") {
                    flutter::EncodableMap map;
                    const char* name = vst3_get_active_shm_name();
                    uintptr_t addr = reinterpret_cast<uintptr_t>(vst3_get_active_shm_ptr());
                    map[flutter::EncodableValue("shmName")] = flutter::EncodableValue(name ? std::string(name) : std::string(""));
                    map[flutter::EncodableValue("address")] = flutter::EncodableValue(static_cast<int64_t>(addr));
                    map[flutter::EncodableValue("totalSize")] = flutter::EncodableValue(static_cast<int64_t>(VST3_SHM_TOTAL_SIZE));
                    map[flutter::EncodableValue("maxSamples")] = flutter::EncodableValue(static_cast<int64_t>(VST3_SHM_MAX_SAMPLES));
                    result->Success(flutter::EncodableValue(map));
                } else {
                    result->NotImplemented();
                }
            });
    }

    static inline std::mutex sTimerMutex;
    static inline std::unordered_map<UINT_PTR, WinFlutterHost*> sPendingTimers;

    static void registerTimer(UINT_PTR id, WinFlutterHost* host) {
        std::lock_guard<std::mutex> lock(sTimerMutex);
        sPendingTimers[id] = host;
    }

    static void unregisterTimer(UINT_PTR id) {
        std::lock_guard<std::mutex> lock(sTimerMutex);
        sPendingTimers.erase(id);
    }

    static void CALLBACK timerProc(HWND hwnd, UINT msg, UINT_PTR id, DWORD time) {
        KillTimer(nullptr, id);
        WinFlutterHost* host = nullptr;
        {
            std::lock_guard<std::mutex> lock(sTimerMutex);
            auto it = sPendingTimers.find(id);
            if (it != sPendingTimers.end()) {
                host = it->second;
                sPendingTimers.erase(it);
            }
        }
        if (host) {
            host->pendingTimerId = 0;
            host->mount();
        }
    }
};
#endif // FLUTTER_VST3_HAS_FLUTTER

struct ParamRowControls {
    Steinberg::Vst::ParamID id{0};
    HWND nameHwnd{nullptr};
    HWND valHwnd{nullptr};
    HWND trackbarHwnd{nullptr};
};

class WinNativeEditorHost {
public:
    HWND hwnd{nullptr};
    EditController* controller{nullptr};
    std::string pluginName;
    std::vector<ParamRowControls> rows;
    HFONT fontTitle{nullptr};
    HFONT fontSubtitle{nullptr};
    HFONT fontLabel{nullptr};
    HFONT fontValue{nullptr};
    HFONT fontFooter{nullptr};
    HBRUSH bgBrush{nullptr};
    HPEN sepPen{nullptr};
    bool inScroll{false};

    static constexpr const wchar_t* kClassName = L"FlutterVst3NativeWin32View";

    static void registerClass(HINSTANCE hInst) {
        static bool registered = false;
        if (registered) return;

        INITCOMMONCONTROLSEX icex{};
        icex.dwSize = sizeof(icex);
        icex.dwICC = ICC_BAR_CLASSES;
        InitCommonControlsEx(&icex);

        WNDCLASSEXW wc{};
        wc.cbSize = sizeof(WNDCLASSEXW);
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = &WinNativeEditorHost::wndProc;
        wc.hInstance = hInst;
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = CreateSolidBrush(RGB(23, 23, 28));
        wc.lpszClassName = kClassName;
        RegisterClassExW(&wc);
        registered = true;
    }

    bool init(HWND parent, EditController* ctrl, const std::string& name, int w, int h) {
        controller = ctrl;
        pluginName = name;
        HINSTANCE hInst = (HINSTANCE)GetWindowLongPtrW(parent, GWLP_HINSTANCE);
        if (!hInst) hInst = GetModuleHandleW(nullptr);
        registerClass(hInst);

        hwnd = CreateWindowExW(
            0, kClassName, L"",
            WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
            0, 0, w, h, parent, nullptr, hInst, this
        );
        return hwnd != nullptr;
    }

    void shutdown() {
        if (hwnd) {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
            DestroyWindow(hwnd);
            hwnd = nullptr;
        }
        rows.clear();
        if (bgBrush) { DeleteObject(bgBrush); bgBrush = nullptr; }
        if (sepPen) { DeleteObject(sepPen); sepPen = nullptr; }
        if (fontTitle) { DeleteObject(fontTitle); fontTitle = nullptr; }
        if (fontSubtitle) { DeleteObject(fontSubtitle); fontSubtitle = nullptr; }
        if (fontLabel) { DeleteObject(fontLabel); fontLabel = nullptr; }
        if (fontValue) { DeleteObject(fontValue); fontValue = nullptr; }
        if (fontFooter) { DeleteObject(fontFooter); fontFooter = nullptr; }
    }

    void updateParam(Steinberg::Vst::ParamID pid, Steinberg::Vst::ParamValue val) {
        if (!hwnd || inScroll) return;
        for (auto& row : rows) {
            if (row.id == pid) {
                int pos = static_cast<int>(std::round(val * 1000.0));
                SendMessageW(row.trackbarHwnd, TBM_SETPOS, TRUE, pos);
                updateValueLabel(row, val);
                break;
            }
        }
    }

    void updateValueLabel(const ParamRowControls& row, double val) {
        if (!row.valHwnd || !controller) return;
        Steinberg::Vst::String128 str{};
        std::wstring text;
        if (controller->getParamStringByValue(row.id, val, str) == Steinberg::kResultTrue) {
            char ascii[128] = {0};
            Steinberg::UString128(str).toAscii(ascii, sizeof(ascii));
            if (ascii[0] != '\0') {
                int needed = MultiByteToWideChar(CP_UTF8, 0, ascii, -1, nullptr, 0);
                if (needed > 1) {
                    text.resize(needed - 1);
                    MultiByteToWideChar(CP_UTF8, 0, ascii, -1, text.data(), needed);
                }
            }
        }
        if (text.empty()) {
            wchar_t buf[32];
            swprintf_s(buf, L"%.1f%%", val * 100.0);
            text = buf;
        }
        SetWindowTextW(row.valHwnd, text.c_str());
    }

private:
    static LRESULT CALLBACK wndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
        if (msg == WM_NCCREATE) {
            auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
            SetWindowLongPtrW(hWnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
            return DefWindowProcW(hWnd, msg, wParam, lParam);
        }

        auto* self = reinterpret_cast<WinNativeEditorHost*>(GetWindowLongPtrW(hWnd, GWLP_USERDATA));
        if (!self) return DefWindowProcW(hWnd, msg, wParam, lParam);

        switch (msg) {
        case WM_CREATE: {
            self->onCreate(hWnd);
            return 0;
        }
        case WM_HSCROLL: {
            HWND trackbar = (HWND)lParam;
            if (!trackbar || !self->controller) return 0;
            for (auto& row : self->rows) {
                if (row.trackbarHwnd == trackbar) {
                    self->inScroll = true;
                    int pos = (int)SendMessageW(trackbar, TBM_GETPOS, 0, 0);
                    double normVal = pos / 1000.0;
                    self->controller->beginEdit(row.id);
                    self->controller->setParamNormalized(row.id, normVal);
                    self->controller->performEdit(row.id, normVal);
                    self->controller->endEdit(row.id);
                    self->updateValueLabel(row, normVal);
                    self->inScroll = false;
                    break;
                }
            }
            return 0;
        }
        case WM_CTLCOLORSTATIC: {
            HDC hdc = (HDC)wParam;
            HWND ctrlHwnd = (HWND)lParam;
            SetBkMode(hdc, TRANSPARENT);
            bool isVal = false;
            for (const auto& r : self->rows) {
                if (r.valHwnd == ctrlHwnd) { isVal = true; break; }
            }
            if (isVal) {
                SetTextColor(hdc, RGB(64, 192, 255));
            } else {
                SetTextColor(hdc, RGB(230, 230, 235));
            }
            return (LRESULT)self->bgBrush;
        }
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hWnd, &ps);
            RECT rc;
            GetClientRect(hWnd, &rc);
            FillRect(hdc, &rc, self->bgBrush);

            SelectObject(hdc, self->sepPen);
            MoveToEx(hdc, 24, 64, nullptr);
            LineTo(hdc, rc.right - 24, 64);

            EndPaint(hWnd, &ps);
            return 0;
        }
        case WM_SIZE: {
            int newW = LOWORD(lParam);
            for (auto& row : self->rows) {
                if (row.valHwnd) {
                    SetWindowPos(row.valHwnd, nullptr, newW - 134, 0, 110, 18, SWP_NOSIZE | SWP_NOZORDER);
                }
                if (row.trackbarHwnd) {
                    SetWindowPos(row.trackbarHwnd, nullptr, 24, 0, newW - 48, 24, SWP_NOMOVE | SWP_NOZORDER);
                }
            }
            InvalidateRect(hWnd, nullptr, FALSE);
            return 0;
        }
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    void onCreate(HWND hWnd) {
        bgBrush = CreateSolidBrush(RGB(23, 23, 28));
        sepPen = CreatePen(PS_SOLID, 1, RGB(45, 45, 55));

        fontTitle = CreateFontW(20, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        fontSubtitle = CreateFontW(13, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                   OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                   DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        fontLabel = CreateFontW(15, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        fontValue = CreateFontW(14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                DEFAULT_PITCH | FF_DONTCARE, L"Consolas");
        fontFooter = CreateFontW(12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

        HINSTANCE hInst = (HINSTANCE)GetWindowLongPtrW(hWnd, GWLP_HINSTANCE);
        RECT rc;
        GetClientRect(hWnd, &rc);
        int w = rc.right - rc.left;
        if (w <= 0) w = 540;

        std::wstring widePluginName = L"VST3 Plugin";
        if (!pluginName.empty()) {
            int needed = MultiByteToWideChar(CP_UTF8, 0, pluginName.c_str(), -1, nullptr, 0);
            if (needed > 1) {
                widePluginName.resize(needed - 1);
                MultiByteToWideChar(CP_UTF8, 0, pluginName.c_str(), -1, widePluginName.data(), needed);
            }
        }
        HWND hTitle = CreateWindowExW(0, L"STATIC", widePluginName.c_str(),
                                      WS_CHILD | WS_VISIBLE | SS_LEFT,
                                      24, 14, 350, 24, hWnd, nullptr, hInst, nullptr);
        SendMessageW(hTitle, WM_SETFONT, (WPARAM)fontTitle, TRUE);

        HWND hSub = CreateWindowExW(0, L"STATIC", L"flutter_vst3 \u2022 Pure Dart DSP & UI",
                                    WS_CHILD | WS_VISIBLE | SS_LEFT,
                                    24, 40, 350, 18, hWnd, nullptr, hInst, nullptr);
        SendMessageW(hSub, WM_SETFONT, (WPARAM)fontSubtitle, TRUE);

        if (controller) {
            int count = controller->getParameterCount();
            int y = 78;
            for (int i = 0; i < count; ++i) {
                Steinberg::Vst::ParameterInfo info{};
                if (controller->getParameterInfo(i, info) != Steinberg::kResultTrue) continue;

                ParamRowControls row;
                row.id = info.id;

                char asciiTitle[128] = {0};
                Steinberg::UString128(info.title).toAscii(asciiTitle, sizeof(asciiTitle));
                std::wstring nameW = L"Param";
                if (asciiTitle[0] != '\0') {
                    int needed = MultiByteToWideChar(CP_UTF8, 0, asciiTitle, -1, nullptr, 0);
                    if (needed > 1) {
                        nameW.resize(needed - 1);
                        MultiByteToWideChar(CP_UTF8, 0, asciiTitle, -1, nameW.data(), needed);
                    }
                }
                row.nameHwnd = CreateWindowExW(0, L"STATIC", nameW.c_str(),
                                               WS_CHILD | WS_VISIBLE | SS_LEFT,
                                               24, y, w - 160, 18, hWnd, nullptr, hInst, nullptr);
                SendMessageW(row.nameHwnd, WM_SETFONT, (WPARAM)fontLabel, TRUE);

                row.valHwnd = CreateWindowExW(0, L"STATIC", L"",
                                              WS_CHILD | WS_VISIBLE | SS_RIGHT,
                                              w - 134, y, 110, 18, hWnd, nullptr, hInst, nullptr);
                SendMessageW(row.valHwnd, WM_SETFONT, (WPARAM)fontValue, TRUE);

                double currentVal = controller->getParamNormalized(info.id);
                int initPos = static_cast<int>(std::round(currentVal * 1000.0));
                row.trackbarHwnd = CreateWindowExW(0, TRACKBAR_CLASSW, L"",
                                                   WS_CHILD | WS_VISIBLE | TBS_HORZ | TBS_NOTICKS,
                                                   24, y + 22, w - 48, 24, hWnd,
                                                   (HMENU)(UINT_PTR)(10000 + i), hInst, nullptr);
                SendMessageW(row.trackbarHwnd, TBM_SETRANGEMIN, FALSE, 0);
                SendMessageW(row.trackbarHwnd, TBM_SETRANGEMAX, FALSE, 1000);
                SendMessageW(row.trackbarHwnd, TBM_SETPOS, TRUE, initPos);

                updateValueLabel(row, currentVal);
                rows.push_back(row);

                y += 56;
            }

            HWND hFooter = CreateWindowExW(0, L"STATIC", L"Preallocated Zero-Copy Shared Memory DSP",
                                           WS_CHILD | WS_VISIBLE | SS_CENTER,
                                           24, y + 10, w - 48, 16, hWnd, nullptr, hInst, nullptr);
            SendMessageW(hFooter, WM_SETFONT, (WPARAM)fontFooter, TRUE);
        }
    }
};

#elif defined(__linux__)
#include <dlfcn.h>
#include <sys/stat.h>
#include <gtk/gtk.h>
#include <gtk/gtkx.h>

#if defined(__linux__) && defined(FLUTTER_VST3_HAS_FLUTTER)
#include <flutter_linux/flutter_linux.h>

struct LinuxFlutterHost {
    GtkWidget* plug{nullptr};
    guint idleSourceId{0};
    void* parentWindow{nullptr};
    int width{600};
    int height{650};
    bool mounted{false};

    static inline GtkWidget* sSharedPlug{nullptr};
    static inline FlView* sSharedView{nullptr};
    static inline FlMethodChannel* sSharedChannel{nullptr};
    static inline Steinberg::Vst::EditController* sActiveController{nullptr};

    static std::string getModuleDirectory() {
        Dl_info info;
        if (dladdr(reinterpret_cast<void*>(&createEmbeddedFlutterView), &info) && info.dli_fname) {
            std::string path(info.dli_fname);
            size_t lastSlash = path.find_last_of('/');
            if (lastSlash != std::string::npos) {
                return path.substr(0, lastSlash);
            }
        }
        return "";
    }

    static bool checkHasFlutter() {
        std::string modDir = getModuleDirectory();
        if (modDir.empty()) return false;
        std::string assetsDir = modDir + "/data/flutter_assets";
        struct stat st;
        return (stat(assetsDir.c_str(), &st) == 0 && S_ISDIR(st.st_mode));
    }

    bool init(void* parentX11, Steinberg::Vst::EditController* ctrl, int w, int h) {
        fprintf(stderr, "[vst3_flutter] LinuxFlutterHost::init: parentX11=%p, size=%dx%d\n",
                parentX11, w, h);
        setenv("GDK_BACKEND", "x11", 1);
        gdk_set_allowed_backends("x11");
        if (!gtk_init_check(nullptr, nullptr)) return false;
        parentWindow = parentX11;
        width = w;
        height = h;
        mounted = false;
        sActiveController = ctrl;

        // Post-mount via GLib timeout so it executes on the platform thread
        // AFTER the host Dart FFI call (openEditorWindow) has returned to the event loop.
        // This avoids Dart VM asserting "CreateIsolate expects there to be no current isolate"
        // when the second Flutter engine spins up its isolate.
        idleSourceId = g_timeout_add(50, +[](gpointer data) -> gboolean {
            auto* self = static_cast<LinuxFlutterHost*>(data);
            self->idleSourceId = 0;
            self->mount();
            return G_SOURCE_REMOVE;
        }, this);
        return true;
    }

    static void onMethodCall(FlMethodChannel* ch, FlMethodCall* methodCall, gpointer userData) {
        const gchar* name = fl_method_call_get_name(methodCall);
        FlValue* args = fl_method_call_get_args(methodCall);
        auto* ctrl = sActiveController;

        if (g_strcmp0(name, "getInitialParameters") == 0) {
            g_autoptr(FlValue) map = fl_value_new_map();
            if (ctrl) {
                int count = ctrl->getParameterCount();
                for (int i = 0; i < count; ++i) {
                    Steinberg::Vst::ParameterInfo info{};
                    if (ctrl->getParameterInfo(i, info) == Steinberg::kResultTrue) {
                        g_autofree gchar* key = g_strdup_printf("%u", info.id);
                        fl_value_set_string_take(
                            map, key,
                            fl_value_new_float(ctrl->getParamNormalized(info.id)));
                    }
                }
            }
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
            fl_method_call_respond(methodCall, resp, nullptr);
        } else if (g_strcmp0(name, "setParameter") == 0) {
            if (ctrl && args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
                FlValue* idVal = fl_value_lookup_string(args, "id");
                FlValue* valVal = fl_value_lookup_string(args, "value");
                if (idVal && valVal) {
                    int64_t pid = (fl_value_get_type(idVal) == FL_VALUE_TYPE_INT)
                        ? fl_value_get_int(idVal)
                        : static_cast<int64_t>(fl_value_get_float(idVal));
                    double val = (fl_value_get_type(valVal) == FL_VALUE_TYPE_FLOAT)
                        ? fl_value_get_float(valVal)
                        : static_cast<double>(fl_value_get_int(valVal));
                    ctrl->beginEdit(pid);
                    ctrl->setParamNormalized(pid, val);
                    ctrl->performEdit(pid, val);
                    ctrl->endEdit(pid);
                }
            }
            g_autoptr(FlValue) ret = fl_value_new_bool(TRUE);
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_success_response_new(ret));
            fl_method_call_respond(methodCall, resp, nullptr);
        } else if (g_strcmp0(name, "getSharedMemoryInfo") == 0) {
            g_autoptr(FlValue) map = fl_value_new_map();
            const char* shmName = vst3_get_active_shm_name();
            uintptr_t addr = reinterpret_cast<uintptr_t>(vst3_get_active_shm_ptr());
            fl_value_set_string_take(map, "shmName", fl_value_new_string(shmName ? shmName : ""));
            fl_value_set_string_take(map, "address", fl_value_new_int(static_cast<int64_t>(addr)));
            fl_value_set_string_take(map, "totalSize", fl_value_new_int(static_cast<int64_t>(VST3_SHM_TOTAL_SIZE)));
            fl_value_set_string_take(map, "maxSamples", fl_value_new_int(static_cast<int64_t>(VST3_SHM_MAX_SAMPLES)));
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
            fl_method_call_respond(methodCall, resp, nullptr);
        } else {
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
            fl_method_call_respond(methodCall, resp, nullptr);
        }
    }

    void mount() {
        fprintf(stderr, "[vst3_flutter] LinuxFlutterHost::mount: mounted=%d, parentWindow=%p, sSharedPlug=%p\n",
                mounted ? 1 : 0, parentWindow, sSharedPlug);
        if (mounted || !parentWindow) return;
        mounted = true;

        Display* xdpy = gdk_x11_get_default_xdisplay();

        if (!sSharedPlug) {
            sSharedPlug = gtk_plug_new((Window)(uintptr_t)parentWindow);
            if (!sSharedPlug) {
                fprintf(stderr, "flutter_vst3: gtk_plug_new failed. VST3 GUI embedding on Linux requires an X11 backend (GDK_BACKEND=x11).\n");
                return;
            }
            g_object_ref_sink(sSharedPlug);
            gtk_widget_set_size_request(sSharedPlug, width, height);
            gtk_widget_realize(sSharedPlug);
            gtk_widget_show(sSharedPlug);

            gdk_gl_context_clear_current();

            std::string modDir = getModuleDirectory();
            std::string assetsPath = modDir + "/data/flutter_assets";
            std::string icuPath = modDir + "/data/icudtl.dat";

            FlDartProject* proj = fl_dart_project_new();
            fl_dart_project_set_assets_path(proj, const_cast<gchar*>(assetsPath.c_str()));
            fl_dart_project_set_icu_data_path(proj, const_cast<gchar*>(icuPath.c_str()));

            std::string aotPath = modDir + "/lib/libapp.so";
            struct stat aotSt;
            if (stat(aotPath.c_str(), &aotSt) != 0) {
                aotPath = modDir + "/libapp.so";
            }
            if (stat(aotPath.c_str(), &aotSt) == 0) {
                fprintf(stderr, "[vst3_flutter] Using AOT library: %s\n", aotPath.c_str());
                fl_dart_project_set_aot_library_path(proj, aotPath.c_str());
            } else {
                fprintf(stderr, "[vst3_flutter] Warning: No libapp.so found in %s/lib or %s\n",
                        modDir.c_str(), modDir.c_str());
            }

            sSharedView = fl_view_new(proj);
            g_object_ref_sink(sSharedView);

            FlEngine* engine = fl_view_get_engine(sSharedView);
            FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
            g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
            sSharedChannel = fl_method_channel_new(messenger, "flutter_vst3/parameters", FL_METHOD_CODEC(codec));
            fl_method_channel_set_method_call_handler(sSharedChannel, onMethodCall, nullptr, nullptr);

            gtk_container_add(GTK_CONTAINER(sSharedPlug), GTK_WIDGET(sSharedView));
        } else {
            // Re-embed existing persistent plug into the new parentWindow if different
            GdkWindow* plugWin = gtk_widget_get_window(sSharedPlug);
            if (plugWin && xdpy) {
                Window plugXid = gdk_x11_window_get_xid(plugWin);
                if (plugXid) {
                    Window currentParent = 0;
                    Window rootRet = 0;
                    Window* childrenRet = nullptr;
                    unsigned int nchildrenRet = 0;
                    if (XQueryTree(xdpy, plugXid, &rootRet, &currentParent, &childrenRet, &nchildrenRet)) {
                        if (childrenRet) XFree(childrenRet);
                    }
                    if (currentParent != (Window)(uintptr_t)parentWindow) {
                        XReparentWindow(xdpy, plugXid, (Window)(uintptr_t)parentWindow, 0, 0);
                    }
                    XResizeWindow(xdpy, plugXid, width, height);
                }
            }
        }

        plug = sSharedPlug;
        gtk_widget_set_size_request(plug, width, height);
        gtk_widget_show_all(plug);

        GdkWindow* plugWin = gtk_widget_get_window(plug);
        if (plugWin) {
            gdk_window_show(plugWin);
            Window plugXid = gdk_x11_window_get_xid(plugWin);
            if (xdpy && plugXid) {
                XMapRaised(xdpy, plugXid);
                XFlush(xdpy);
            }
        }

        // On reopen, synchronize parameters and notify Flutter UI that host is attached
        if (sSharedChannel) {
            fl_method_channel_invoke_method(sSharedChannel, "onHostAttached", nullptr, nullptr, nullptr, nullptr);
            if (sActiveController) {
                int count = sActiveController->getParameterCount();
                for (int i = 0; i < count; ++i) {
                    Steinberg::Vst::ParameterInfo info{};
                    if (sActiveController->getParameterInfo(i, info) == Steinberg::kResultTrue) {
                        updateParam(info.id, sActiveController->getParamNormalized(info.id));
                    }
                }
            }
        }
    }

    void updateParam(Steinberg::Vst::ParamID pid, Steinberg::Vst::ParamValue val) {
        if (!sSharedChannel) return;
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "id", fl_value_new_int(static_cast<int64_t>(pid)));
        fl_value_set_string_take(args, "value", fl_value_new_float(static_cast<double>(val)));
        fl_method_channel_invoke_method(sSharedChannel, "onParameterChanged", args, nullptr, nullptr, nullptr);
    }

    void shutdown() {
        fprintf(stderr, "[vst3_flutter] LinuxFlutterHost::shutdown called (plug=%p)\n", plug);
        if (idleSourceId != 0) {
            g_source_remove(idleSourceId);
            idleSourceId = 0;
        }
        if (sSharedChannel) {
            fl_method_channel_invoke_method(sSharedChannel, "onHostDetached", nullptr, nullptr, nullptr, nullptr);
        }
        if (sSharedPlug) {
            gtk_widget_hide(sSharedPlug);
        }
        gdk_gl_context_clear_current();
        plug = nullptr;
        sActiveController = nullptr;
        mounted = false;
        parentWindow = nullptr;
    }
};
#else
struct LinuxFlutterHost {
    static bool checkHasFlutter() { return false; }
    bool init(void*, Steinberg::Vst::EditController*, int, int) { return false; }
    void updateParam(Steinberg::Vst::ParamID, Steinberg::Vst::ParamValue) {}
    void shutdown() {}
};
#endif

struct LinuxNativeParamRow {
    Steinberg::Vst::ParamID id{0};
    GtkWidget* valLabel{nullptr};
    GtkWidget* scale{nullptr};
    GtkAdjustment* adj{nullptr};
};

class LinuxNativeEditorHost {
public:
    GtkWidget* plug{nullptr};
    GtkWidget* mainBox{nullptr};
    GtkCssProvider* cssProvider{nullptr};
    Steinberg::Vst::EditController* controller{nullptr};
    std::string pluginName;
    std::vector<LinuxNativeParamRow> rows;
    bool inScroll{false};
    guint idleSourceId{0};
    void* parentWindow{nullptr};
    int width{540};
    int height{400};

    bool init(void* parentX11, Steinberg::Vst::EditController* ctrl, const std::string& name, int w, int h) {
        setenv("GDK_BACKEND", "x11", 1);
        gdk_set_allowed_backends("x11");
        if (!gtk_init_check(nullptr, nullptr)) return false;
        parentWindow = parentX11;
        controller = ctrl;
        pluginName = name;
        width = w;
        height = h;

        mount();
        return true;
    }

    void mount() {
        if (!parentWindow) return;
        plug = gtk_plug_new((Window)(uintptr_t)parentWindow);
        if (!plug) return;

        gtk_widget_set_size_request(plug, width, height);
        gtk_style_context_add_class(gtk_widget_get_style_context(plug), "vst3-native-editor");

        if (!cssProvider) {
            cssProvider = gtk_css_provider_new();
            const char* css =
                ".vst3-native-editor, .vst3-native-editor box { background-color: #17171c; color: #e6e6eb; }"
                ".vst3-native-editor label.plugin-title { font-size: 16pt; font-weight: bold; color: #ffffff; }"
                ".vst3-native-editor label.plugin-sub { font-size: 10pt; color: #888899; }"
                ".vst3-native-editor label.param-name { font-size: 11pt; font-weight: 600; color: #e6e6eb; }"
                ".vst3-native-editor label.param-val { font-size: 11pt; font-weight: bold; color: #40c0ff; font-family: monospace; }"
                ".vst3-native-editor label.footer { font-size: 9pt; color: #666677; }"
                ".vst3-native-editor scale contents trough { min-height: 4px; background-color: #2d2d37; border-radius: 2px; }"
                ".vst3-native-editor scale contents trough highlight { background-color: #40c0ff; border-radius: 2px; }"
                ".vst3-native-editor scale contents trough slider { min-width: 16px; min-height: 16px; margin: -6px; border-radius: 8px; background-color: #ffffff; }";
            gtk_css_provider_load_from_data(cssProvider, css, -1, nullptr);
            gtk_style_context_add_provider_for_screen(
                gdk_screen_get_default(),
                GTK_STYLE_PROVIDER(cssProvider),
                GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        mainBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
        gtk_style_context_add_class(gtk_widget_get_style_context(mainBox), "vst3-native-editor");
        gtk_widget_set_margin_start(mainBox, 24);
        gtk_widget_set_margin_end(mainBox, 24);
        gtk_widget_set_margin_top(mainBox, 16);
        gtk_widget_set_margin_bottom(mainBox, 16);

        // Title
        GtkWidget* titleLbl = gtk_label_new(pluginName.empty() ? "VST3 Plugin" : pluginName.c_str());
        gtk_widget_set_halign(titleLbl, GTK_ALIGN_START);
        gtk_style_context_add_class(gtk_widget_get_style_context(titleLbl), "plugin-title");
        gtk_box_pack_start(GTK_BOX(mainBox), titleLbl, FALSE, FALSE, 0);

        // Subtitle
        GtkWidget* subLbl = gtk_label_new("flutter_vst3 \u2022 Pure Dart DSP & UI");
        gtk_widget_set_halign(subLbl, GTK_ALIGN_START);
        gtk_style_context_add_class(gtk_widget_get_style_context(subLbl), "plugin-sub");
        gtk_box_pack_start(GTK_BOX(mainBox), subLbl, FALSE, FALSE, 0);

        // Separator
        GtkWidget* sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
        gtk_box_pack_start(GTK_BOX(mainBox), sep, FALSE, FALSE, 6);

        // Parameter rows
        rows.clear();
        if (controller) {
            int count = controller->getParameterCount();
            for (int i = 0; i < count; ++i) {
                Steinberg::Vst::ParameterInfo info{};
                if (controller->getParameterInfo(i, info) != Steinberg::kResultTrue) continue;

                LinuxNativeParamRow row;
                row.id = info.id;

                char asciiTitle[128] = {0};
                Steinberg::UString128(info.title).toAscii(asciiTitle, sizeof(asciiTitle));

                GtkWidget* rowBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);

                GtkWidget* headerBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
                GtkWidget* nameLbl = gtk_label_new(asciiTitle[0] != '\0' ? asciiTitle : "Param");
                gtk_widget_set_halign(nameLbl, GTK_ALIGN_START);
                gtk_style_context_add_class(gtk_widget_get_style_context(nameLbl), "param-name");
                gtk_box_pack_start(GTK_BOX(headerBox), nameLbl, TRUE, TRUE, 0);

                row.valLabel = gtk_label_new("");
                gtk_widget_set_halign(row.valLabel, GTK_ALIGN_END);
                gtk_style_context_add_class(gtk_widget_get_style_context(row.valLabel), "param-val");
                gtk_box_pack_start(GTK_BOX(headerBox), row.valLabel, FALSE, FALSE, 0);

                gtk_box_pack_start(GTK_BOX(rowBox), headerBox, FALSE, FALSE, 0);

                double currentVal = controller->getParamNormalized(info.id);
                row.adj = gtk_adjustment_new(currentVal, 0.0, 1.0, 0.001, 0.01, 0.0);
                row.scale = gtk_scale_new(GTK_ORIENTATION_HORIZONTAL, row.adj);
                gtk_scale_set_draw_value(GTK_SCALE(row.scale), FALSE);
                gtk_box_pack_start(GTK_BOX(rowBox), row.scale, FALSE, FALSE, 0);

                struct CallbackData {
                    LinuxNativeEditorHost* self;
                    Steinberg::Vst::ParamID paramId;
                    size_t rowIndex;
                };
                auto* cbData = new CallbackData{this, info.id, rows.size()};
                g_signal_connect_data(row.adj, "value-changed",
                    G_CALLBACK(+[](GtkAdjustment* adj, gpointer user_data) {
                        auto* data = static_cast<CallbackData*>(user_data);
                        if (data->self->inScroll || !data->self->controller) return;
                        data->self->inScroll = true;
                        double val = gtk_adjustment_get_value(adj);
                        data->self->controller->beginEdit(data->paramId);
                        data->self->controller->setParamNormalized(data->paramId, val);
                        data->self->controller->performEdit(data->paramId, val);
                        data->self->controller->endEdit(data->paramId);
                        data->self->updateValueLabel(data->self->rows[data->rowIndex], val);
                        data->self->inScroll = false;
                    }),
                    cbData,
                    [](gpointer data, GClosure*) { delete static_cast<CallbackData*>(data); },
                    G_CONNECT_AFTER);

                updateValueLabel(row, currentVal);
                gtk_box_pack_start(GTK_BOX(mainBox), rowBox, FALSE, FALSE, 4);
                rows.push_back(row);
            }

            // Footer
            GtkWidget* footer = gtk_label_new("Preallocated Zero-Copy Shared Memory DSP");
            gtk_widget_set_halign(footer, GTK_ALIGN_CENTER);
            gtk_style_context_add_class(gtk_widget_get_style_context(footer), "footer");
            gtk_box_pack_start(GTK_BOX(mainBox), footer, FALSE, FALSE, 8);
        }

        gtk_container_add(GTK_CONTAINER(plug), mainBox);
        gtk_widget_show_all(plug);

        GdkWindow* plugWin = gtk_widget_get_window(plug);
        if (plugWin) {
            gdk_window_show(plugWin);
            Window plugXid = gdk_x11_window_get_xid(plugWin);
            Display* xdpy = gdk_x11_get_default_xdisplay();
            if (xdpy && plugXid) {
                XMapRaised(xdpy, plugXid);
                XFlush(xdpy);
            }
        }
    }

    void updateValueLabel(LinuxNativeParamRow& row, double val) {
        if (!row.valLabel) return;
        char buf[128];
        if (controller) {
            Steinberg::Vst::String128 str128;
            if (controller->getParamStringByValue(row.id, val, str128) == Steinberg::kResultTrue) {
                Steinberg::UString128(str128).toAscii(buf, sizeof(buf));
                gtk_label_set_text(GTK_LABEL(row.valLabel), buf);
                return;
            }
        }
        snprintf(buf, sizeof(buf), "%.2f", val);
        gtk_label_set_text(GTK_LABEL(row.valLabel), buf);
    }

    void updateParam(Steinberg::Vst::ParamID paramId, Steinberg::Vst::ParamValue val) {
        if (inScroll) return;
        for (auto& r : rows) {
            if (r.id == paramId) {
                inScroll = true;
                if (r.adj) {
                    gtk_adjustment_set_value(r.adj, val);
                }
                updateValueLabel(r, val);
                inScroll = false;
                break;
            }
        }
    }

    void shutdown() {
        if (idleSourceId != 0) {
            g_source_remove(idleSourceId);
            idleSourceId = 0;
        }
        if (cssProvider) {
            gtk_style_context_remove_provider_for_screen(
                gdk_screen_get_default(),
                GTK_STYLE_PROVIDER(cssProvider));
            g_object_unref(cssProvider);
            cssProvider = nullptr;
        }
        if (plug) {
            gtk_widget_destroy(plug);
            plug = nullptr;
            mainBox = nullptr;
        }
        rows.clear();
        parentWindow = nullptr;
    }
};
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
        fprintf(stderr, "[vst3_flutter] EmbeddedFlutterView::attached: parent=%p, type='%s', hasFlutter=%d\n",
                parent, type ? type : "", hasFlutter_ ? 1 : 0);
        if (!parent || !type) return kInvalidArgument;
        parentView_ = parent;
#if defined(_WIN32)
#if defined(FLUTTER_VST3_HAS_FLUTTER)
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
            winHost_.init((HWND)parent, controller_, pluginName_, 540, h);
        }
#elif defined(__linux__)
        if (hasFlutter_) {
            bool ok = linuxFlutterHost_.init(parent, controller_, 600, 650);
            if (!ok) {
                hasFlutter_ = false;
            }
        }
        if (!hasFlutter_) {
            int count = controller_ ? controller_->getParameterCount() : 0;
            int h = (std::max)(280, 74 + count * 56 + 36);
            linuxNativeHost_.init(parent, controller_, pluginName_, 540, h);
        }
#endif
        return kResultTrue;
    }

    tresult PLUGIN_API removed() override {
        fprintf(stderr, "[vst3_flutter] EmbeddedFlutterView::removed called\n");
        cleanup();
        if (viewHolder_ && *viewHolder_ == this) *viewHolder_ = nullptr;
        return kResultTrue;
    }

    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        int count = controller_ ? controller_->getParameterCount() : 0;
        size->left = 0;
        size->top = 0;
        size->right = hasFlutter_ ? 600 : 540;
        size->bottom = hasFlutter_ ? 650 : (std::max)(280, 74 + count * 56 + 36);
        return kResultTrue;
    }

    tresult PLUGIN_API onSize(ViewRect* r) override {
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
#endif
        return kResultTrue;
    }

    tresult PLUGIN_API setFrame(IPlugFrame* frame) override { return kResultTrue; }
    tresult PLUGIN_API canResize() override { return kResultFalse; }
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
    void cleanup() {
        fprintf(stderr, "[vst3_flutter] cleanup() called, hasFlutter=%d\n", hasFlutter_ ? 1 : 0);
#if defined(_WIN32)
#if defined(FLUTTER_VST3_HAS_FLUTTER)
        if (hasFlutter_) {
            winFlutterHost_.shutdown();
        }
#endif
        winHost_.shutdown();
#elif defined(__linux__)
        if (hasFlutter_) {
            linuxFlutterHost_.shutdown();
        }
        linuxNativeHost_.shutdown();
#endif
        parentView_ = nullptr;
    }

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