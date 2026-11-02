// Win32 parents and a message loop.
#include "editor_host_platform.h"
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <chrono>
#include <cstdio>
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
    HWND window = CreateWindowExW(WS_EX_TOPMOST, kClassName, L"parent", WS_POPUP | WS_VISIBLE, 0, 0, 600, 650,
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
unsigned long long platformCaptureHash(void* window) {
    RECT r; check(GetWindowRect(asWindow(window), &r), "capture rect");
    HDC screen = GetDC(nullptr), memory = CreateCompatibleDC(screen);
    HBITMAP bitmap = CreateCompatibleBitmap(screen, 540, 180);
    auto old = SelectObject(memory, bitmap);
    check(BitBlt(memory, 0, 0, 540, 180, screen, r.left, r.top + 60, SRCCOPY), "capture BitBlt");
    unsigned long long hash = 14695981039346656037ULL;
    for (int y = 0; y < 180; ++y) for (int x = 0; x < 540; ++x) {
        auto pixel = GetPixel(memory, x, y); check(pixel != CLR_INVALID, "capture GetPixel");
        for (int b = 0; b < 4; ++b) { hash ^= (pixel >> (b * 8)) & 255; hash *= 1099511628211ULL; }
    }
    SelectObject(memory, old); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr, screen);
    return hash;
}
void platformMove(void* window, int x, int y) {
    RECT r; check(GetWindowRect(asWindow(window), &r), "pointer rect");
    INPUT input{}; input.type = INPUT_MOUSE;
    input.mi.dx = (r.left + x) * 65535 / (GetSystemMetrics(SM_CXSCREEN) - 1);
    input.mi.dy = (r.top + y) * 65535 / (GetSystemMetrics(SM_CYSCREEN) - 1);
    input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
    check(SendInput(1, &input, sizeof(input)) == 1, "SendInput move"); platformPump(150);
}
void platformButton(void* window, int x, int y, DWORD flags) {
    platformMove(window, x, y); INPUT input{}; input.type = INPUT_MOUSE; input.mi.dwFlags = flags;
    check(SendInput(1, &input, sizeof(input)) == 1, "SendInput button"); platformPump(150);
}
void platformPress(void* w, int x, int y) { platformButton(w, x, y, MOUSEEVENTF_LEFTDOWN); }
void platformRelease(void*, int, int) {
    INPUT input{}; input.type = INPUT_MOUSE; input.mi.dwFlags = MOUSEEVENTF_LEFTUP;
    check(SendInput(1, &input, sizeof(input)) == 1, "SendInput release"); platformPump(150);
}
bool platformCanCapture() { return true; }
// Reads the screen, since a swap chain's pixels don't reach the window's own DC.
bool platformRendered(void* window) {
    RECT rect;
    check(GetWindowRect(asWindow(window), &rect) != 0, "Rendering: GetWindowRect");
    const int width = rect.right - rect.left, height = rect.bottom - rect.top;
    HDC screen = GetDC(nullptr);
    check(screen != nullptr, "Rendering: GetDC");
    HDC memory = CreateCompatibleDC(screen);
    HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
    SelectObject(memory, bitmap);
    check(BitBlt(memory, 0, 0, width, height, screen, rect.left, rect.top, SRCCOPY) != 0, "Rendering: BitBlt");
    const COLORREF first = GetPixel(memory, 0, 0);
    bool varied = false;
    for (int y = 0; y < height; y += 2) for (int x = 0; x < width; x += 2)
        varied |= GetPixel(memory, x, y) != first;
    std::printf("captured %dx%d, first pixel %06lx, varied %d\n", width, height,
        static_cast<unsigned long>(first), varied ? 1 : 0);
    DeleteObject(bitmap);
    DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    return varied;
}
