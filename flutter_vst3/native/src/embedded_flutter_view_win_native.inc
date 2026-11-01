
struct ParamRowControls {
    Steinberg::Vst::ParamID id{0};
    HWND nameHwnd{nullptr};
    HWND valHwnd{nullptr};
    HWND trackbarHwnd{nullptr};
    bool editing{false};
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

    static const wchar_t* className() {
        static const auto name = editorClassName(L"FlutterVst3NativeWin32View");
        return name.c_str();
    }

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
        wc.lpszClassName = className();
        RegisterClassExW(&wc);
        registered = true;
    }

    bool init(HWND parent, EditController* ctrl, const std::string& name, int w, int h) {
        controller = ctrl;
        pluginName = name;
        HINSTANCE hInst = editorModule();
        if (!hInst) return false;
        registerClass(hInst);

        hwnd = CreateWindowExW(
            0, className(), L"", 
            WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
            0, 0, w, h, parent, nullptr, hInst, this
        );
        return hwnd != nullptr;
    }

    void shutdown() {
        for (const auto& row : rows)
            if (row.editing && controller) controller->endEdit(row.id);
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
                    const auto action = LOWORD(wParam);
                    if (!row.editing) {
                        self->controller->beginEdit(row.id);
                        row.editing = true;
                    }
                    if (action != TB_ENDTRACK) {
                        self->controller->setParamNormalized(row.id, normVal);
                        self->controller->performEdit(row.id, normVal);
                    }
                    if (action == TB_ENDTRACK) {
                        self->controller->endEdit(row.id);
                        row.editing = false;
                    }
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

            HWND hFooter = CreateWindowExW(0, L"STATIC", L"Shared Memory DSP",
                                           WS_CHILD | WS_VISIBLE | SS_CENTER,
                                           24, y + 10, w - 48, 16, hWnd, nullptr, hInst, nullptr);
            SendMessageW(hFooter, WM_SETFONT, (WPARAM)fontFooter, TRUE);
        }
    }
};
