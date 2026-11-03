#pragma once
#include <cstdlib>
#if defined(_WIN32)
#include <windows.h>
std::wstring dllDirectory() {
    wchar_t value[32768]{};
    auto size = GetDllDirectoryW(32768, value);
    check(size < 32768, "H12 directory read");
    return std::wstring(value, size);
}
void environmentInvariant() {
    const auto original = dllDirectory();
    wchar_t directory[32768]{};
    check(GetWindowsDirectoryW(directory, 32768) > 0, "H12 Windows directory");
    for (const auto& expected : {original, std::wstring(directory)}) {
        check(SetDllDirectoryW(expected.c_str()) != 0, "H12 set directory");
        { Editor a; platformPump(1500); check(dllDirectory() == expected, "H12 DLL directory changed on attach"); }
        check(dllDirectory() == expected, "H12 DLL directory changed on close");
    }
    check(SetDllDirectoryW(original.c_str()) != 0, "H12 restore directory");
    puts("PASS H12 DLL directory invariant");
}
#elif defined(__linux__)
#include <gtk/gtk.h>
void initializedBackendInvariant() {
    auto* display = gdk_display_get_default();
    check(display != nullptr, "H13 GTK was not initialized");
    const std::string backend = G_OBJECT_TYPE_NAME(display);
    check(backend == "GdkX11Display", "H13 expected initialized X11 backend");
    { Editor a; platformPump(500); }
    check(gdk_display_get_default() == display, "H13 initialized display replaced");
    check(std::string(G_OBJECT_TYPE_NAME(display)) == backend, "H13 initialized backend changed");
}
void environmentInvariant() {
    const char* prior = getenv("GDK_BACKEND");
    const bool present = prior != nullptr;
    const std::string original = present ? prior : "";
    for (const char* value : {static_cast<const char*>(nullptr), "x11"}) {
        check((value ? setenv("GDK_BACKEND", value, 1) : unsetenv("GDK_BACKEND")) == 0, "H13 setup");
        { Editor a; platformPump(1500); }
        const char* actual = getenv("GDK_BACKEND");
        check(value ? actual && std::string(actual) == value : actual == nullptr, "H13 GDK_BACKEND changed");
    }
    initializedBackendInvariant();
    check((present ? setenv("GDK_BACKEND", original.c_str(), 1) : unsetenv("GDK_BACKEND")) == 0, "H13 restore");
    puts("PASS H13 GDK_BACKEND invariant before and after GTK initialization");
}
#else
void environmentInvariant() { puts("PASS environment invariant not applicable on Cocoa"); }
#endif
void immediateClose() {
    for (bool update : {false, true}) {
        Editor a;
        if (update) check(a.controller->setParamNormalized(0, 0.37) == kResultTrue, "H15 set value");
        a.view->removed(); a.view->setFrame(nullptr); a.view = nullptr;
        platformPump(500);
        if (update) check(a.controller->getParamNormalized(0) == 0.37, "H15 queued value changed");
    }
    puts("PASS H15 immediate close");
}
