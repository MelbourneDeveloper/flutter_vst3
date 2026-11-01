// Win32 parents and a message loop.
#include "editor_host_platform.h"
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <chrono>
using namespace Steinberg;
using Clock = std::chrono::steady_clock;

namespace {
BasicFrame frame;
const wchar_t* const kClassName = L"EditorHostTestParent";
HWND asWindow(void* window) { return static_cast<HWND>(window); }
BOOL CALLBACK findVisible(HWND child, LPARAM found) {
    *reinterpret_cast<bool*>(found) |= IsWindowVisible(child) != FALSE;
    return TRUE;
}
}

void platformInit() {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    wc.lpszClassName = kClassName;
    check(RegisterClassExW(&wc) != 0, "RegisterClassExW");
}
void platformShutdown() {}
IPlugFrame* platformFrame() { return &frame; }
const char* platformViewType() { return kPlatformTypeHWND; }
long long platformProcessId() { return GetCurrentProcessId(); }
void* platformCreateWindow() {
    HWND window = CreateWindowExW(0, kClassName, L"parent", WS_POPUP | WS_VISIBLE, 0, 0, 600, 650,
        nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    check(window != nullptr, "CreateWindowExW");
    return window;
}
void platformDestroyWindow(void* window) { DestroyWindow(asWindow(window)); }
void platformPump(int ms) {
    const auto end = Clock::now() + std::chrono::milliseconds(ms);
    while (Clock::now() < end) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        Sleep(1);
    }
}
bool platformHasVisibleChild(void* window) {
    bool found = false;
    EnumChildWindows(asWindow(window), findVisible, reinterpret_cast<LPARAM>(&found));
    return found;
}
bool platformCanCapture() { return true; }
bool platformRendered(void* window) {
    HDC source = GetDC(asWindow(window));
    check(source != nullptr, "Rendering: GetDC");
    HDC memory = CreateCompatibleDC(source);
    HBITMAP bitmap = CreateCompatibleBitmap(source, 600, 650);
    SelectObject(memory, bitmap);
    check(PrintWindow(asWindow(window), memory, PW_RENDERFULLCONTENT) != 0, "Rendering: PrintWindow");
    const COLORREF first = GetPixel(memory, 0, 0);
    bool varied = false;
    for (int y = 0; y < 650; y += 2) for (int x = 0; x < 600; x += 2)
        varied |= GetPixel(memory, x, y) != first;
    DeleteObject(bitmap);
    DeleteDC(memory);
    ReleaseDC(asWindow(window), source);
    return varied;
}
