// Copyright (c) 2025
// Flutter Embedder API types for VST3 plugins
// Minimal definitions to compile without full Flutter SDK

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Flutter engine handle
typedef struct _FlutterEngine* FlutterEngine;
typedef struct _FlutterEngineAOTData* FlutterEngineAOTData;

// Result codes
typedef enum {
    kSuccess = 0,
    kInvalidLibraryVersion,
    kInvalidArguments,
    kInternalInconsistency,
} FlutterEngineResult;

// Renderer types
typedef enum {
    kOpenGL,
    kSoftware,
    kMetal,
    kVulkan,
} FlutterRendererType;

// Task runner
typedef struct {
    size_t struct_size;
    void* task_runner;
    void (*task)(void* task_runner, void* task);
} FlutterTask;

typedef struct {
    size_t struct_size;
    void* user_data;
    bool (*runs_task_on_current_thread_callback)(void* user_data);
    void (*post_task_callback)(FlutterTask task, uint64_t target_time, void* user_data);
} FlutterTaskRunnerDescription;

typedef struct {
    size_t struct_size;
    const FlutterTaskRunnerDescription* platform_task_runner;
    const FlutterTaskRunnerDescription* render_task_runner;
    const FlutterTaskRunnerDescription* raster_task_runner;
    const FlutterTaskRunnerDescription* ui_task_runner;
} FlutterCustomTaskRunners;

// Platform messages
typedef struct {
    size_t struct_size;
    const char* channel;
    const uint8_t* message;
    size_t message_size;
    const void* response_handle;
} FlutterPlatformMessage;

typedef void (*FlutterPlatformMessageCallback)(
    const FlutterPlatformMessage* message,
    void* user_data);

// Renderer configuration
typedef struct {
    size_t struct_size;
    bool (*make_current)(void* user_data);
    bool (*clear_current)(void* user_data);
    bool (*present)(void* user_data);
    uint32_t (*fbo_callback)(void* user_data);
    bool (*make_resource_current)(void* user_data);
    void* (*gl_proc_resolver)(const char* name);
    bool fbo_reset_after_present;
    void* surface_transformation;
} FlutterOpenGLRendererConfig;

// Forward declare
typedef struct {
    size_t struct_size;
} FlutterMetalTexture;

typedef struct {
    FlutterMetalTexture* texture;
} FlutterMetalExternalTexture;

typedef struct {
    size_t struct_size;
    bool (*make_current)(void* user_data);
    bool (*clear_current)(void* user_data);
    bool (*present)(void* user_data);
    uint32_t (*fbo_callback)(void* user_data);
    bool (*make_resource_current)(void* user_data);
    bool fbo_reset_after_present;
    void* surface_transformation;
    FlutterMetalExternalTexture (*get_texture)(void* user_data, const FlutterMetalTexture* texture);
} FlutterMetalRendererConfig;

typedef struct {
    size_t struct_size;
} FlutterSoftwareRendererConfig;

typedef struct {
    FlutterRendererType type;
    union {
        FlutterOpenGLRendererConfig open_gl;
        FlutterSoftwareRendererConfig software;
        FlutterMetalRendererConfig metal;
    };
} FlutterRendererConfig;

// AOT data
typedef enum {
    kFlutterEngineAOTDataSourceTypeElfPath,
} FlutterEngineAOTDataSourceType;

typedef struct {
    FlutterEngineAOTDataSourceType type;
    const char* elf_path;
} FlutterEngineAOTDataSource;

// Project arguments
typedef struct {
    size_t struct_size;
    const char* assets_path;
    const char* main_path__unused__;
    const char* packages_path__unused__;
    const char* icu_data_path;
    int command_line_argc;
    const char* const* command_line_argv;
    FlutterPlatformMessageCallback platform_message_callback;
    const char** dart_entrypoint_argv;
    int dart_entrypoint_argc;
    const char* log_message_callback__unused__;
    const char* log_tag;
    void* on_pre_engine_restart_callback__unused__;
    const char* dart_entrypoint;
    FlutterEngineAOTData aot_data;
    const FlutterCustomTaskRunners* custom_task_runners;
} FlutterProjectArgs;

// Engine version - must match the Flutter SDK version
#define FLUTTER_ENGINE_VERSION 1

// Function declarations (implemented by Flutter engine library)
FlutterEngineResult FlutterEngineRun(
    size_t version,
    const FlutterRendererConfig* config,
    const FlutterProjectArgs* args,
    void* user_data,
    FlutterEngine* engine_out);

FlutterEngineResult FlutterEngineShutdown(FlutterEngine engine);

FlutterEngineResult FlutterEngineCreateAOTData(
    const FlutterEngineAOTDataSource* source,
    FlutterEngineAOTData* data_out);

FlutterEngineResult FlutterEngineCollectAOTData(FlutterEngineAOTData data);

FlutterEngineResult FlutterEngineSendPlatformMessage(
    FlutterEngine engine,
    const FlutterPlatformMessage* message);

FlutterEngineResult FlutterEngineSendPlatformMessageResponse(
    FlutterEngine engine,
    const void* handle,
    const uint8_t* data,
    size_t data_length);

#ifdef __cplusplus
}  // extern "C"
#endif