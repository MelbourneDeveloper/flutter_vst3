// Copyright (c) 2025
// Flutter Engine Embedder for VST3 plugins
// Runs Flutter IN THE SAME PROCESS as the VST plugin

#include <memory>
#include <string>
#include <vector>
#include <thread>
#include <chrono>

#ifdef __APPLE__
#include <dlfcn.h>
#include <mach-o/dyld.h>
#endif

// Flutter Embedder API headers
#include "flutter_embedder.h"

namespace Steinberg::Vst {

// Global Flutter engine instance - ONE ENGINE PER PROCESS
static FlutterEngine g_flutter_engine = nullptr;
static FlutterEngineAOTData g_aot_data = nullptr;

// Platform-specific rendering surface
struct FlutterRenderSurface {
    void* native_window;
    size_t width;
    size_t height;
};

class FlutterEmbedder {
public:
    static bool InitializeEngine(const std::string& assets_path,
                                const std::string& icu_data_path,
                                const std::string& aot_library_path) {
        if (g_flutter_engine != nullptr) {
            // Engine already initialized - SAME PROCESS!
            return true;
        }

        // Load Flutter engine library
        void* flutter_lib = nullptr;
#ifdef __APPLE__
        flutter_lib = dlopen("FlutterMacOS.framework/FlutterMacOS", RTLD_LAZY);
        if (!flutter_lib) {
            // Try alternative paths
            flutter_lib = dlopen("@rpath/FlutterMacOS.framework/FlutterMacOS", RTLD_LAZY);
        }
#elif defined(_WIN32)
        flutter_lib = LoadLibrary("flutter_engine.dll");
#else
        flutter_lib = dlopen("libflutter_engine.so", RTLD_LAZY);
#endif

        if (!flutter_lib) {
            fprintf(stderr, "FAILED to load Flutter engine library!\n");
            return false;
        }

        // Create Flutter project arguments
        FlutterProjectArgs project_args = {};
        project_args.struct_size = sizeof(FlutterProjectArgs);
        project_args.assets_path = assets_path.c_str();
        project_args.icu_data_path = icu_data_path.c_str();
        
        // Load AOT compiled Dart code if available
        if (!aot_library_path.empty()) {
            FlutterEngineAOTDataSource aot_source = {};
            aot_source.type = kFlutterEngineAOTDataSourceTypeElfPath;
            aot_source.elf_path = aot_library_path.c_str();
            
            if (FlutterEngineCreateAOTData(&aot_source, &g_aot_data) == kSuccess) {
                project_args.aot_data = g_aot_data;
            }
        }

        // Configure platform-specific rendering
        FlutterRendererConfig renderer_config = {};
        
#ifdef __APPLE__
        // Metal renderer for macOS
        renderer_config.type = kMetal;
        renderer_config.metal = {
            .struct_size = sizeof(FlutterMetalRendererConfig),
            .make_current = [](void* user_data) -> bool { return true; },
            .clear_current = [](void* user_data) -> bool { return true; },
            .present = [](void* user_data) -> bool { return true; },
            .fbo_callback = [](void* user_data) -> uint32_t { return 0; },
            .make_resource_current = [](void* user_data) -> bool { return true; },
            .fbo_reset_after_present = false,
            .surface_transformation = nullptr,
            .get_texture = [](void* user_data, const FlutterMetalTexture* texture) -> FlutterMetalExternalTexture {
                return {};
            }
        };
#else
        // OpenGL renderer for other platforms
        renderer_config.type = kOpenGL;
        renderer_config.open_gl = {
            .struct_size = sizeof(FlutterOpenGLRendererConfig),
            .make_current = [](void* user_data) -> bool { return true; },
            .clear_current = [](void* user_data) -> bool { return true; },
            .present = [](void* user_data) -> bool { return true; },
            .fbo_callback = [](void* user_data) -> uint32_t { return 0; },
            .make_resource_current = [](void* user_data) -> bool { return true; },
            .gl_proc_resolver = nullptr,
            .fbo_reset_after_present = false,
            .surface_transformation = nullptr,
        };
#endif

        // Custom task runner for VST3 thread integration
        FlutterTaskRunnerDescription platform_task_runner = {};
        platform_task_runner.struct_size = sizeof(FlutterTaskRunnerDescription);
        platform_task_runner.user_data = nullptr;
        platform_task_runner.runs_task_on_current_thread_callback = [](void* user_data) -> bool {
            return true; // VST3 UI thread
        };
        platform_task_runner.post_task_callback = [](FlutterTask task, uint64_t target_time, void* user_data) {
            // Execute immediately for now - integrate with VST3 message loop later
            if (task.task) {
                task.task(task.task_runner, &task);
            }
        };

        FlutterCustomTaskRunners custom_task_runners = {};
        custom_task_runners.struct_size = sizeof(FlutterCustomTaskRunners);
        custom_task_runners.platform_task_runner = &platform_task_runner;

        project_args.custom_task_runners = &custom_task_runners;

        // Dart entry point - this is where the Flutter UI starts IN THIS PROCESS
        project_args.dart_entrypoint = "main";
        
        // Command line arguments to tell Flutter it's embedded in VST3
        const char* dart_args[] = {
            "--disable-service-auth-codes",
            "--enable-dart-profiling",
            "--vst3-embedded",
            nullptr
        };
        project_args.dart_entrypoint_argc = 3;
        project_args.dart_entrypoint_argv = dart_args;

        // Platform message handler for parameter synchronization
        project_args.platform_message_callback = [](const FlutterPlatformMessage* message, void* user_data) {
            if (strcmp(message->channel, "vst3/parameters") == 0) {
                // Handle parameter changes from Flutter UI
                // This runs IN THE SAME PROCESS as audio processing!
                HandleParameterMessage(message);
            }
        };

        // Initialize the Flutter engine IN THIS PROCESS
        FlutterEngineResult result = FlutterEngineRun(
            FLUTTER_ENGINE_VERSION,
            &renderer_config,
            &project_args,
            nullptr, // user_data
            &g_flutter_engine
        );

        if (result != kSuccess) {
            fprintf(stderr, "FAILED to start Flutter engine! Result: %d\n", result);
            return false;
        }

        fprintf(stdout, "Flutter engine started IN-PROCESS successfully!\n");
        return true;
    }

    static void ShutdownEngine() {
        if (g_flutter_engine) {
            FlutterEngineShutdown(g_flutter_engine);
            g_flutter_engine = nullptr;
        }
        if (g_aot_data) {
            FlutterEngineCollectAOTData(g_aot_data);
            g_aot_data = nullptr;
        }
    }

    static FlutterEngine GetEngine() {
        return g_flutter_engine;
    }

    // Send parameter updates to Flutter UI (runs in SAME PROCESS)
    static void SendParameterToFlutter(int param_id, double value) {
        if (!g_flutter_engine) return;

        // Create message for Flutter
        std::string message = "{\"method\":\"parameterChanged\",\"id\":" + 
                            std::to_string(param_id) + 
                            ",\"value\":" + std::to_string(value) + "}";

        FlutterPlatformMessage platform_message = {};
        platform_message.struct_size = sizeof(FlutterPlatformMessage);
        platform_message.channel = "vst3/parameters";
        platform_message.message = reinterpret_cast<const uint8_t*>(message.c_str());
        platform_message.message_size = message.size();

        FlutterEngineSendPlatformMessage(g_flutter_engine, &platform_message);
    }

private:
    static void HandleParameterMessage(const FlutterPlatformMessage* message) {
        // Parse parameter change from Flutter UI
        // This is called IN THE SAME PROCESS
        // Parse JSON and update VST parameter - implementation would go here
        
        // Send response
        if (message->response_handle) {
            FlutterEngineSendPlatformMessageResponse(
                g_flutter_engine,
                message->response_handle,
                nullptr, 0
            );
        }
    }
};

// Factory function to create embedded Flutter view
void* createFlutterEmbedderInstance() {
    // Initialize Flutter engine IN THIS PROCESS if not already done
    FlutterEmbedder::InitializeEngine(
        "flutter_assets",     // Assets path
        "icudtl.dat",         // ICU data
        "app.so"              // AOT library
    );
    
    return FlutterEmbedder::GetEngine();
}

// C++ class implementation for embedded_flutter_view.mm
class FlutterEmbedder {
public:
    FlutterEmbedder() : engine_(nullptr) {}
    
    ~FlutterEmbedder() {
        if (engine_) {
            FlutterEngineShutdown(engine_);
        }
    }
    
    void* createEngine() {
        // Initialize Flutter engine IN THIS PROCESS
        if (!InitializeEngine("flutter_assets", "icudtl.dat", "")) {
            return nullptr;
        }
        engine_ = GetEngine();
        return engine_;
    }
    
    bool attachToParent(void* parent, void* flutter_engine) {
        if (!parent || !flutter_engine) return false;
        
        // Attach Flutter view to VST host window
        // Platform-specific implementation required
#ifdef __APPLE__
        // NSView attachment for macOS
        return attachToNSView(parent, flutter_engine);
#elif defined(_WIN32)
        // HWND attachment for Windows
        return attachToHWND(parent, flutter_engine);
#else
        // X11 attachment for Linux
        return attachToX11Window(parent, flutter_engine);
#endif
    }
    
    bool launchApp(void* flutter_engine, const std::string& command_line) {
        if (!flutter_engine) return false;
        
        // Send launch command to Flutter app
        std::string launch_message = "{\"method\":\"launch\",\"args\":\"" + command_line + "\"}";
        
        FlutterPlatformMessage platform_message = {};
        platform_message.struct_size = sizeof(FlutterPlatformMessage);
        platform_message.channel = "vst3/control";
        platform_message.message = reinterpret_cast<const uint8_t*>(launch_message.c_str());
        platform_message.message_size = launch_message.size();
        
        FlutterEngineResult result = FlutterEngineSendPlatformMessage(
            static_cast<FlutterEngine>(flutter_engine),
            &platform_message
        );
        
        return result == kSuccess;
    }
    
    void resize(int width, int height) {
        if (!engine_) return;
        
        // Send resize event to Flutter
        std::string resize_message = "{\"method\":\"resize\",\"width\":" + 
                                   std::to_string(width) + 
                                   ",\"height\":" + std::to_string(height) + "}";
        
        FlutterPlatformMessage platform_message = {};
        platform_message.struct_size = sizeof(FlutterPlatformMessage);
        platform_message.channel = "vst3/window";
        platform_message.message = reinterpret_cast<const uint8_t*>(resize_message.c_str());
        platform_message.message_size = resize_message.size();
        
        FlutterEngineSendPlatformMessage(engine_, &platform_message);
    }
    
    void shutdown(void* flutter_engine) {
        if (flutter_engine) {
            FlutterEngineShutdown(static_cast<FlutterEngine>(flutter_engine));
        }
        engine_ = nullptr;
    }
    
private:
    FlutterEngine engine_;
    
#ifdef __APPLE__
    bool attachToNSView(void* parent, void* flutter_engine) {
        // Implementation for macOS NSView attachment
        // This would create a Flutter view and add it to the parent NSView
        return true; // Stub implementation
    }
#elif defined(_WIN32)
    bool attachToHWND(void* parent, void* flutter_engine) {
        // Implementation for Windows HWND attachment
        return true; // Stub implementation
    }
#else
    bool attachToX11Window(void* parent, void* flutter_engine) {
        // Implementation for Linux X11 window attachment
        return true; // Stub implementation
    }
#endif
    
    // Use existing static methods
    bool InitializeEngine(const std::string& assets_path,
                         const std::string& icu_data_path,
                         const std::string& aot_library_path) {
        return FlutterEmbedder::InitializeEngine(assets_path, icu_data_path, aot_library_path);
    }
    
    FlutterEngine GetEngine() {
        return FlutterEmbedder::GetEngine();
    }
};

} // namespace Steinberg::Vst