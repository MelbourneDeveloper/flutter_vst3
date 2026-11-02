
#if defined(FLUTTER_VST3_HAS_FLUTTER)
class WinFlutterHost {
public:
    std::function<void()> onFailure;
    UINT_PTR watchdog{0};
    static inline bool sUiAlive{false};
    static constexpr UINT_PTR kHeldButtonTimer = 1;
    static inline bool sEngineFailed{false};
    static inline WinFlutterHost* sOwner{nullptr};
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

    static HWND getHolderHwnd() {
        static HWND holder = nullptr;
        if (!holder) {
            HINSTANCE hInst = editorModule();
            static const auto name = editorClassName(L"FlutterVst3HolderWindow");
            WNDCLASSEXW wc{};
            wc.cbSize = sizeof(WNDCLASSEXW);
            wc.lpfnWndProc = DefWindowProcW;
            wc.hInstance = hInst;
            wc.lpszClassName = name.c_str();
            RegisterClassExW(&wc);

            holder = CreateWindowExW(
                0, name.c_str(), L"FlutterHolder",
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
        if (sEngineFailed || moduleDir.empty()) return false;
        std::wstring assetsPath = moduleDir + L"\\data\\flutter_assets";
        DWORD attr = GetFileAttributesW(assetsPath.c_str());
        return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY)
            && GetFileAttributesW((moduleDir + L"\\data\\icudtl.dat").c_str()) != INVALID_FILE_ATTRIBUTES
            && (GetFileAttributesW((moduleDir + L"\\data\\app.so").c_str()) != INVALID_FILE_ATTRIBUTES
                || GetFileAttributesW((assetsPath + L"\\kernel_blob.bin").c_str()) != INVALID_FILE_ATTRIBUTES);
    }

    bool init(HWND parent, EditController* ctrl, int w, int h) {
        if (sActiveController && sActiveController != ctrl) return false;
        controller = ctrl;
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
            sFlDll = LoadLibraryExW(dllPath.c_str(), nullptr,
                LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
            if (!sFlDll) return false;
        }

        // Post-mount via thread timer so it executes on the main platform thread
        // AFTER the Dart FFI call (openEditorWindow) has returned to the event loop.
        UINT_PTR tid = SetTimer(nullptr, 0, 10, &WinFlutterHost::timerProc);
        if (tid == 0) return false;
        pendingTimerId = tid;
        registerTimer(tid, this);
        sActiveController = ctrl;
        sOwner = this;
        return true;
    }

    void mount() {
        if (!flutter_vst3::ownsEditor(sActiveController, controller) || mounted.load() || !parentHwnd) return;
        mounted = true;

        if (!sSharedVc) {
            std::wstring moduleDir = getModuleDirectory();
            std::wstring assetsPath = moduleDir + L"\\data\\flutter_assets";
            std::wstring icuPath = moduleDir + L"\\data\\icudtl.dat";

            FlutterDesktopEngineProperties props{};
            props.assets_path = assetsPath.c_str();
            props.icu_data_path = icuPath.c_str();
            // Release engines load the app from here. Debug bundles have no app.so.
            const std::wstring aotPath = moduleDir + L"\\data\\app.so";
            props.aot_library_path = GetFileAttributesW(aotPath.c_str()) != INVALID_FILE_ATTRIBUTES ? aotPath.c_str() : nullptr;
#ifndef VST3_FLUTTER_ENTRYPOINT
#error VST3_FLUTTER_ENTRYPOINT must name the plugin Dart entrypoint
#endif
            props.dart_entrypoint = VST3_FLUTTER_ENTRYPOINT;
            props.ui_thread_policy = RunOnPlatformThread;
            props.impeller_switch = DisabledImpeller;

            sSharedEngine = FlutterDesktopEngineCreate(&props);
            if (!sSharedEngine) { fail(); return; }
            watchdog = SetTimer(nullptr, 0, flutter_vst3::kFlutterStartTimeoutMs,
                +[](HWND, UINT, UINT_PTR id, DWORD) {
                    KillTimer(nullptr, id);
                    if (!sOwner) return;
                    sOwner->watchdog = 0;
                    if (flutter_vst3::flutterStartFailed(sUiAlive, sEngineFailed, sActiveController != nullptr)) sOwner->fail();
                });
            if (!watchdog) { fail(); return; }

            setupMethodChannel();
            if (!sSharedChannel) { fail(); return; }

            if (!FlutterDesktopEngineRun(sSharedEngine, VST3_FLUTTER_ENTRYPOINT)) { fail(); return; }

            sSharedVc = FlutterDesktopViewControllerCreate(width, height, sSharedEngine);
            if (!sSharedVc) { sSharedEngine = nullptr; fail(); return; }

            FlutterDesktopViewRef view = FlutterDesktopViewControllerGetView(sSharedVc);
            if (!view) { fail(); return; }

            sSharedFlutterHwnd = FlutterDesktopViewGetHWND(view);
            if (!sSharedFlutterHwnd) { fail(); return; }

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
        ignoreHeldButton();

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

    void fail() {
        if (watchdog) { KillTimer(nullptr, watchdog); watchdog = 0; }
        sEngineFailed = true;
        sSharedChannel.reset();
        sSharedMessenger.reset();
        if (sSharedVc) FlutterDesktopViewControllerDestroy(sSharedVc);
        else if (sSharedEngine) FlutterDesktopEngineDestroy(sSharedEngine);
        sSharedVc = nullptr;
        sSharedEngine = nullptr;
        sSharedFlutterHwnd = flutterHwnd = nullptr;
        sActiveController = nullptr;
        sOwner = nullptr;
        mounted = false;
        if (onFailure) onFailure();
    }

    static bool leftButtonHeld() { return (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0; }

    static VOID CALLBACK enableWhenReleased(HWND window, UINT, UINT_PTR timer, DWORD) {
        if (leftButtonHeld()) return;
        KillTimer(window, timer);
        EnableWindow(window, TRUE);
    }

    /// A button held since before this window appeared isn't a click on it. If
    /// Flutter saw only the end of one, its next drag would never finish.
    static void ignoreHeldButton() {
        if (!leftButtonHeld()) return;
        EnableWindow(sSharedFlutterHwnd, FALSE);
        SetTimer(sSharedFlutterHwnd, kHeldButtonTimer, 20, enableWhenReleased);
    }

    void shutdown() {
        if (watchdog) { KillTimer(nullptr, watchdog); watchdog = 0; }
        if (pendingTimerId != 0) {
            KillTimer(nullptr, pendingTimerId);
            unregisterTimer(pendingTimerId);
            pendingTimerId = 0;
        }

        if (!flutter_vst3::ownsEditor(sActiveController, controller)) return;
        if (sSharedChannel) {
            sSharedChannel->InvokeMethod("onHostDetached", nullptr);
        }

        if (sSharedFlutterHwnd) {
            KillTimer(sSharedFlutterHwnd, kHeldButtonTimer);
            EnableWindow(sSharedFlutterHwnd, TRUE);
            ShowWindow(sSharedFlutterHwnd, SW_HIDE);
            SetParent(sSharedFlutterHwnd, getHolderHwnd());
        }

        if (sActiveController == controller) {
            sActiveController = nullptr;
        }

        sOwner = nullptr;
        flutterHwnd = nullptr;
        parentHwnd = nullptr;
        mounted = false;
    }

    void updateParam(Steinberg::Vst::ParamID pid, Steinberg::Vst::ParamValue val) {
        if (!flutter_vst3::ownsEditor(sActiveController, controller) || !sSharedChannel) return;
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
                sUiAlive = true;
                auto* ctrl = sActiveController;
                if ((call.method_name() == "beginEdit" || call.method_name() == "endEdit") && ctrl) {
                    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                    if (!args || args->count(flutter::EncodableValue("id")) == 0) {
                        result->Error("INVALID_ARGUMENTS", "Expected parameter id");
                        return;
                    }
                    const auto& id = args->at(flutter::EncodableValue("id"));
                    const auto pid = std::holds_alternative<int32_t>(id)
                        ? std::get<int32_t>(id) : static_cast<int>(std::get<int64_t>(id));
                    call.method_name() == "beginEdit" ? ctrl->beginEdit(pid) : ctrl->endEdit(pid);
                    result->Success(flutter::EncodableValue(true));
                } else if (call.method_name() == "setParameter" && ctrl) {
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
                        applyUiEdit(ctrl, static_cast<Steinberg::Vst::ParamID>(pid), val);
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
                    uintptr_t addr = controllerShmAddress(ctrl);
                    map[flutter::EncodableValue("address")] = flutter::EncodableValue(static_cast<int64_t>(addr));
                    map[flutter::EncodableValue("totalSize")] = flutter::EncodableValue(static_cast<int64_t>(VST3_SHM_TOTAL_SIZE));
                    map[flutter::EncodableValue("maxSamples")] = flutter::EncodableValue(static_cast<int64_t>(VST3_SHM_MAX_SAMPLES));
                    result->Success(flutter::EncodableValue(map));
                } else {
                    result->NotImplemented();
                }
            });
    }

    static inline std::unordered_map<UINT_PTR, WinFlutterHost*> sPendingTimers;

    static void registerTimer(UINT_PTR id, WinFlutterHost* host) {
        sPendingTimers[id] = host;
    }

    static void unregisterTimer(UINT_PTR id) {
        sPendingTimers.erase(id);
    }

    static void CALLBACK timerProc(HWND hwnd, UINT msg, UINT_PTR id, DWORD time) {
        KillTimer(nullptr, id);
        WinFlutterHost* host = nullptr;
        {
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
