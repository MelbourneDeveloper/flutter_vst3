#pragma once
#include <set>
#include <thread>
#include <chrono>
std::set<HWND> consoles;
DWORD workerPid = 0;
bool visibleWorker = false;
BOOL CALLBACK inspectWindow(HWND window, LPARAM) {
    char name[128]{};
    GetClassNameA(window, name, sizeof(name));
    if (std::string(name) == "ConsoleWindowClass") consoles.insert(window);
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    if (pid == workerPid && IsWindowVisible(window)) visibleWorker = true;
    return TRUE;
}
void detachedTest(const char* executable) {
    FreeConsole();
    check(GetConsoleWindow() == nullptr, "test still has console");
    check(EnumWindows(inspectWindow, 0) != 0, "initial EnumWindows failed");
    const auto before = consoles;
    consoles.clear();
    const auto worker = spawnWorker(executable, "worker", "", "");
    workerPid = static_cast<DWORD>(childPid(worker));
    std::this_thread::sleep_for(std::chrono::milliseconds(1500));
    check(childAlive(worker), "console worker died prematurely");
    check(EnumWindows(inspectWindow, 0) != 0, "worker EnumWindows failed");
    childStop(worker, 0);
    check(!visibleWorker, "worker owns a visible window");
    for (auto window : consoles) check(before.count(window) == 1, "new ConsoleWindowClass window");
}
int windowsChild(const char* mode) {
    if (std::string(mode) == "worker") { Sleep(10000); return 0; }
    check(std::string(mode) == "detached", "unknown child mode");
    char executable[MAX_PATH]{};
    check(GetModuleFileNameA(nullptr, executable, MAX_PATH) != 0, "executable lookup failed");
    detachedTest(executable);
    return 0;
}
void windowsTest(const char* executable) {
    std::string command = std::string("\"") + executable + "\" detached";
    STARTUPINFOA startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    check(CreateProcessA(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                         nullptr, nullptr, &startup, &process) != 0, "child mode spawn failed");
    check(WaitForSingleObject(process.hProcess, 15000) == WAIT_OBJECT_0, "child mode timed out");
    DWORD result = 99;
    check(GetExitCodeProcess(process.hProcess, &result) != 0, "child mode status failed");
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    check(result == 0, "detached console test failed");
    std::cout << "PASS detached worker has no visible or new console window\n";
}
