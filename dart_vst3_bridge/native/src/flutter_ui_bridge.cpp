// Flutter UI Bridge for VST3 plugins
// Embeds Flutter engine directly in the VST plugin process

#include "pluginterfaces/gui/iplugview.h"
#include "public.sdk/source/common/pluginview.h"
#include <flutter_embedder.h>
#include <memory>
#include <string>
#include <vector>

namespace Steinberg::Vst {

class FlutterUIView : public CPluginView {
public:
    FlutterUIView(const std::string& flutterAssetPath) 
        : CPluginView(nullptr), assetPath_(flutterAssetPath) {
    }
    
    ~FlutterUIView() override {
        if (engine_) {
            FlutterEngineShutdown(engine_);
            engine_ = nullptr;
        }
    }

    tresult PLUGIN_API attached(void* parent, FIDString type) override {
        if (!parent) return kInvalidArgument;
        
#ifdef __APPLE__
        if (strcmp(type, kPlatformTypeNSView) != 0) {
            return kResultFalse;
        }
        
        // Initialize Flutter Engine
        if (!initializeFlutterEngine()) {
            return kResultFalse;
        }
        
        // Get NSView from Flutter and attach to parent
        FlutterCompositor compositor = {};
        compositor.struct_size = sizeof(FlutterCompositor);
        compositor.user_data = parent;
        compositor.create_backing_store_callback = [](const FlutterBackingStoreConfig* config,
                                                      FlutterBackingStore* backing_store_out,
                                                      void* user_data) -> bool {
            // Create macOS Metal backing store
            backing_store_out->type = kFlutterBackingStoreTypeMetal;
            backing_store_out->metal.struct_size = sizeof(FlutterMetalBackingStore);
            return true;
        };
        
        FlutterProjectArgs args = {};
        args.struct_size = sizeof(FlutterProjectArgs);
        args.assets_path = assetPath_.c_str();
        args.icu_data_path = icuDataPath_.c_str();
        args.compositor = &compositor;
        
        FlutterEngineRunsAOTCompiledDartCode();
        
        FlutterEngineResult result = FlutterEngineRun(
            FLUTTER_ENGINE_VERSION, 
            &FlutterRendererConfig{}, 
            &args, 
            parent, 
            &engine_
        );
        
        if (result != kSuccess) {
            return kResultFalse;
        }
        
        // Send initial parameters to Flutter
        sendParametersToFlutter();
        
#endif
        return kResultOk;
    }
    
    tresult PLUGIN_API removed() override {
        if (engine_) {
            FlutterEngineShutdown(engine_);
            engine_ = nullptr;
        }
        return kResultOk;
    }
    
    tresult PLUGIN_API getSize(ViewRect* size) override {
        if (!size) return kInvalidArgument;
        size->left = 0;
        size->top = 0;
        size->right = 520;
        size->bottom = 380;
        return kResultOk;
    }
    
    // Send parameter updates to Flutter
    void updateParameter(int paramId, double value) {
        if (!engine_) return;
        
        // Use Flutter platform channels to send parameter updates
        std::string channel = "vst3/parameters";
        std::string message = "{\"id\":" + std::to_string(paramId) + 
                            ",\"value\":" + std::to_string(value) + "}";
        
        FlutterPlatformMessage platformMessage = {};
        platformMessage.struct_size = sizeof(FlutterPlatformMessage);
        platformMessage.channel = channel.c_str();
        platformMessage.message = reinterpret_cast<const uint8_t*>(message.c_str());
        platformMessage.message_size = message.size();
        
        FlutterEngineSendPlatformMessage(engine_, &platformMessage);
    }
    
private:
    FlutterEngine engine_ = nullptr;
    std::string assetPath_;
    std::string icuDataPath_;
    
    bool initializeFlutterEngine() {
        // Configure Flutter engine paths
        // These paths should be relative to the VST3 bundle
        assetPath_ = "Contents/Resources/flutter_assets";
        icuDataPath_ = "Contents/Resources/icudtl.dat";
        
        return true;
    }
    
    void sendParametersToFlutter() {
        // Send initial parameter values to Flutter UI
        // This will be called when the view is attached
    }
};

// Factory function to create Flutter UI view
IPlugView* createFlutterUIView(const std::string& flutterAssetPath) {
    return new FlutterUIView(flutterAssetPath);
}

} // namespace Steinberg::Vst