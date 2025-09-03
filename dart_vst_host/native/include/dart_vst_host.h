// VST3 Host interface for Dart
// Generated for cross-platform Dart VST hosting

#pragma once
#include <stdint.h>

#ifdef _WIN32
  #ifdef DART_VST_HOST_EXPORTS
    #define DVH_API __declspec(dllexport)
  #else
    #define DVH_API __declspec(dllimport)
  #endif
#else
  #define DVH_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* DVH_Host;
typedef void* DVH_Plugin;

// Create a VST3 host. Provide sample rate and max block size.
DVH_API DVH_Host dvh_create_host(double sample_rate, int32_t max_block);
// Destroy a previously created host.
DVH_API void      dvh_destroy_host(DVH_Host host);

// Load a plugin from module path. Optional class UID filters which class to instantiate.
DVH_API DVH_Plugin dvh_load_plugin(DVH_Host host, const char* module_path_utf8, const char* class_uid_or_null);
// Unload a previously loaded plugin.
DVH_API void       dvh_unload_plugin(DVH_Plugin p);

// Resume processing on a plugin. Must be called after loading before processing.
DVH_API int32_t dvh_resume(DVH_Plugin p, double sample_rate, int32_t max_block);
// Suspend processing on a plugin.
DVH_API int32_t dvh_suspend(DVH_Plugin p);

// Process stereo audio. Input pointers must be valid arrays of length num_frames. Output will be written in-place.
DVH_API int32_t dvh_process_stereo_f32(DVH_Plugin p,
                                       const float* inL, const float* inR,
                                       float* outL, float* outR,
                                       int32_t num_frames);

// Send a NoteOn to the plugin. Channel and pitch follow MIDI convention. Velocity in [0,1].
DVH_API int32_t dvh_note_on(DVH_Plugin p, int32_t channel, int32_t note, float velocity);
// Send a NoteOff to the plugin.
DVH_API int32_t dvh_note_off(DVH_Plugin p, int32_t channel, int32_t note, float velocity);

// Query number of parameters for a plugin. Returns 0 if no controller present.
DVH_API int32_t dvh_param_count(DVH_Plugin p);
// Query parameter info by index. Fills id, title and units buffers. Returns 1 on success.
DVH_API int32_t dvh_param_info(DVH_Plugin p, int32_t index,
                               int32_t* id_out,
                               char* title_utf8, int32_t title_cap,
                               char* units_utf8, int32_t units_cap);

// Get a parameter value normalized [0,1] by ID.
DVH_API float   dvh_get_param_normalized(DVH_Plugin p, int32_t param_id);
// Set a parameter normalized value. Returns 1 on success.
DVH_API int32_t dvh_set_param_normalized(DVH_Plugin p, int32_t param_id, float normalized);

#ifdef __cplusplus
}
#endif