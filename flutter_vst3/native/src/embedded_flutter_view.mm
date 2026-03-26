// Copyright (c) 2025
// VST3 IPlugView implementation using VST3's distributed architecture
// Communicates via IPC with Dart/Flutter process containing BOTH audio processing AND UI
// Follows VST3's official distributed controller/processor separation pattern

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>
#endif

#include "pluginterfaces/gui/iplugview.h"
#include "base/source/fobject.h"
#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <cstdio>

#ifdef __APPLE__
#include <unistd.h>
#include <sys/wait.h>
#include <mach-o/dyld.h>
#endif

namespace Steinberg::Vst {

class EmbeddedFlutterView : public IPlugView, public FObject {
public:
    EmbeddedFlutterView() : parentView_(nullptr), dartUiProcess_(nullptr), ipcWriteFd_(-1), ipcReadFd_(-1) {
        currentSize_.left = 0;
        currentSize_.top = 0;
        currentSize_.right = 600;
        currentSize_.bottom = 420;
    }
    
    ~EmbeddedFlutterView() {
        cleanup();
    }

    tresult PLUGIN_API isPlatformTypeSupported(FIDString type) override {
#ifdef __APPLE__
        return (strcmp(type, kPlatformTypeNSView) == 0) ? kResultTrue : kResultFalse;
#elif defined(_WIN32)
        return (strcmp(type, kPlatformTypeHWND) == 0) ? kResultTrue : kResultFalse;
#else
        return (strcmp(type, kPlatformTypeX11EmbedWindowID) == 0) ? kResultTrue : kResultFalse;
#endif
    }

    tresult PLUGIN_API attached(void* parent, FIDString type) override {
        if (!parent) return kResultFalse;
        
        parentView_ = parent;
        
        // Launch Dart/Flutter process with IPC (VST3 distributed architecture)
        if (!launchDartUIProcess()) {
            return kResultFalse;
        }
        
        // Attach UI window to parent VST host view
        if (!attachUIToParent()) {
            return kResultFalse;
        }
        
        return kResultTrue;
    }

    tresult PLUGIN_API removed() override {
        cleanup();
        return kResultTrue;
    }

    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        *size = currentSize_;
        return kResultTrue;
    }

    tresult PLUGIN_API onSize(ViewRect* newSize) override {
        if (!newSize) return kInvalidArgument;
        currentSize_ = *newSize;
        
        // Send resize command via IPC to Dart/Flutter UI process
        sendResizeCommand(newSize->right - newSize->left,
                         newSize->bottom - newSize->top);
        
        return kResultTrue;
    }

    tresult PLUGIN_API setFrame(IPlugFrame* frame) override { return kResultTrue; }
    tresult PLUGIN_API canResize() override { return kResultTrue; }
    tresult PLUGIN_API checkSizeConstraint(ViewRect* rect) override { return kResultTrue; }
    tresult PLUGIN_API onWheel(float distance) override { return kResultTrue; }
    tresult PLUGIN_API onKeyDown(char16 key, int16 keyCode, int16 modifiers) override { return kResultTrue; }
    tresult PLUGIN_API onKeyUp(char16 key, int16 keyCode, int16 modifiers) override { return kResultTrue; }
    tresult PLUGIN_API onFocus(TBool state) override { return kResultTrue; }

    REFCOUNT_METHODS(FObject)
    
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, IPlugView::iid, IPlugView)
        return FObject::queryInterface(iid, obj);
    }

private:
    bool launchDartUIProcess() {
        if (uiLaunched_.exchange(true)) return true;
        
        // Create IPC pipes for communication with Dart/Flutter UI process
        int pipeToChild[2], pipeFromChild[2];
        if (pipe(pipeToChild) == -1 || pipe(pipeFromChild) == -1) {
            return false;
        }
        
        // Fork process for Dart/Flutter UI (VST3 distributed architecture)
        pid_t pid = fork();
        if (pid == 0) {
            // Child process: Launch Dart/Flutter executable with --ui flag
            // This process contains BOTH audio processing AND UI in same isolate
            
            // Setup IPC pipes
            dup2(pipeToChild[0], STDIN_FILENO);   // Child reads from parent
            dup2(pipeFromChild[1], STDOUT_FILENO); // Child writes to parent
            
            // Close unused pipe ends
            close(pipeToChild[1]);
            close(pipeFromChild[0]);
            
            // Launch Dart/Flutter executable containing audio processing AND UI
            // Get executable path relative to VST3 bundle location
            std::string execPath = getPluginExecutablePath();
            execl(execPath.c_str(), execPath.c_str(), "--ui", nullptr);
            
            // If execl fails, kill child process
            fprintf(stderr, "CRITICAL VST3 FAILURE: Cannot launch Dart/Flutter UI process!\n");
            _exit(1);
        } else if (pid > 0) {
            // Parent process: VST3 C++ controller
            dartUiProcess_ = reinterpret_cast<void*>(static_cast<intptr_t>(pid));
            
            // Setup IPC file descriptors
            ipcWriteFd_ = pipeToChild[1];   // Parent writes to child
            ipcReadFd_ = pipeFromChild[0];  // Parent reads from child
            
            // Close unused pipe ends
            close(pipeToChild[0]);
            close(pipeFromChild[1]);
            
            // Send initialization command to Dart/Flutter UI process
            sendInitCommand();
            
            return true;
        } else {
            // Fork failed
            return false;
        }
    }
    
    bool attachUIToParent() {
#ifdef __APPLE__
        // On macOS, the Flutter process will create its own NSWindow
        // We need to get the window handle via IPC and attach it to parent
        return attachNSWindow();
#elif defined(_WIN32)
        return attachHWND();
#else
        return attachX11Window();
#endif
    }
    
    void sendInitCommand() {
        if (ipcWriteFd_ == -1) return;
        
        // Send BINARY UI initialization command
        uint8_t initCmd = 0x10; // cmdInitUI
        write(ipcWriteFd_, &initCmd, 1);
    }
    
    void sendResizeCommand(int width, int height) {
        if (ipcWriteFd_ == -1) return;
        
        // Send BINARY resize command with dimensions (LITTLE-ENDIAN)
        uint8_t buffer[9];
        buffer[0] = 0x11; // cmdResize
        // Pack integers in little-endian format to match Dart expectations
        buffer[1] = width & 0xFF;
        buffer[2] = (width >> 8) & 0xFF;
        buffer[3] = (width >> 16) & 0xFF;
        buffer[4] = (width >> 24) & 0xFF;
        buffer[5] = height & 0xFF;
        buffer[6] = (height >> 8) & 0xFF;
        buffer[7] = (height >> 16) & 0xFF;
        buffer[8] = (height >> 24) & 0xFF;
        write(ipcWriteFd_, buffer, 9);
    }
    
#ifdef __APPLE__
    bool attachNSWindow() {
        // Request window handle from Dart/Flutter process via BINARY IPC
        uint8_t getWindowCmd = 0x12; // cmdGetWindow
        write(ipcWriteFd_, &getWindowCmd, 1);
        
        // Read BINARY window handle response 
        uint8_t response[9];
        if (read(ipcReadFd_, response, 9) == 9 && response[0] == 0x12) {
            // Extract window handle from binary response (LITTLE-ENDIAN)
            uint64_t windowHandle = 
                ((uint64_t)response[1]) |
                ((uint64_t)response[2] << 8) |
                ((uint64_t)response[3] << 16) |
                ((uint64_t)response[4] << 24) |
                ((uint64_t)response[5] << 32) |
                ((uint64_t)response[6] << 40) |
                ((uint64_t)response[7] << 48) |
                ((uint64_t)response[8] << 56);
            // Embed the Flutter NSWindow into the VST host view
            return true; // Stub implementation
        }
        return false;
    }
#endif
    
    std::string getPluginExecutablePath() {
        // Get path to Dart executable within VST3 bundle
        // VST3 bundles have structure: PluginName.vst3/Contents/Resources/
#ifdef __APPLE__
        // On macOS, get bundle path and find executable
        char bundlePath[1024];
        uint32_t size = sizeof(bundlePath);
        if (_NSGetExecutablePath(bundlePath, &size) == 0) {
            std::string path(bundlePath);
            // Replace .vst3/Contents/MacOS/PluginName with .vst3/Contents/Resources/echo_processor
            size_t pos = path.find(".vst3/Contents/MacOS/");
            if (pos != std::string::npos) {
                return path.substr(0, pos) + ".vst3/Contents/Resources/echo_processor";
            }
        }
        // Fallback to relative path
        return "./echo_processor";
#elif defined(_WIN32)
        // Windows VST3 bundle structure
        return "./echo_processor.exe";
#else
        // Linux
        return "./echo_processor";
#endif
    }
    
    void cleanup() {
        // Close IPC pipes
        if (ipcWriteFd_ != -1) {
            close(ipcWriteFd_);
            ipcWriteFd_ = -1;
        }
        if (ipcReadFd_ != -1) {
            close(ipcReadFd_);
            ipcReadFd_ = -1;
        }
        
        // Terminate Dart/Flutter UI process
        if (dartUiProcess_) {
            pid_t pid = static_cast<pid_t>(reinterpret_cast<intptr_t>(dartUiProcess_));
            kill(pid, SIGTERM);
            waitpid(pid, nullptr, 0);
            dartUiProcess_ = nullptr;
        }
        
        parentView_ = nullptr;
    }

    void* parentView_;
    void* dartUiProcess_;           // Process handle for Dart/Flutter UI
    int ipcWriteFd_, ipcReadFd_;    // IPC pipe file descriptors
    ViewRect currentSize_;
    std::atomic<bool> uiLaunched_{false};
};

// Factory function
IPlugView* createEmbeddedFlutterView() {
    return new EmbeddedFlutterView();
}

} // namespace Steinberg::Vst