// Copyright (c) 2025
// Flutter Embedder Stubs - Placeholder implementations until Flutter SDK is linked
// This allows the VST plugin to compile and run with placeholder UI

#include "flutter_embedder.h"
#include <stdio.h>

extern "C" {

// Stub implementations for Flutter Embedder API
FlutterEngineResult FlutterEngineRun(
    size_t version,
    const FlutterRendererConfig* config,
    const FlutterProjectArgs* args,
    void* user_data,
    FlutterEngine* engine_out) {
    
    printf("STUB: FlutterEngineRun called - would start Flutter IN-PROCESS here\n");
    
    // Return a fake engine handle
    *engine_out = (FlutterEngine)0x1234;
    return kSuccess;
}

FlutterEngineResult FlutterEngineShutdown(FlutterEngine engine) {
    printf("STUB: FlutterEngineShutdown called\n");
    return kSuccess;
}

FlutterEngineResult FlutterEngineCreateAOTData(
    const FlutterEngineAOTDataSource* source,
    FlutterEngineAOTData* data_out) {
    
    printf("STUB: FlutterEngineCreateAOTData called\n");
    *data_out = (FlutterEngineAOTData)0x5678;
    return kSuccess;
}

FlutterEngineResult FlutterEngineCollectAOTData(FlutterEngineAOTData data) {
    printf("STUB: FlutterEngineCollectAOTData called\n");
    return kSuccess;
}

FlutterEngineResult FlutterEngineSendPlatformMessage(
    FlutterEngine engine,
    const FlutterPlatformMessage* message) {
    
    printf("STUB: FlutterEngineSendPlatformMessage - channel: %s\n", 
           message ? message->channel : "null");
    return kSuccess;
}

FlutterEngineResult FlutterEngineSendPlatformMessageResponse(
    FlutterEngine engine,
    const void* handle,
    const uint8_t* data,
    size_t data_length) {
    
    printf("STUB: FlutterEngineSendPlatformMessageResponse called\n");
    return kSuccess;
}

} // extern "C"