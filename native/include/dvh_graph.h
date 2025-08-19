// Copyright (c) 2025
//
// This header defines the C API for the dynamic graph used by the
// Dart VST host. The graph allows multiple VST3 plug‑ins to be hosted
// simultaneously, with arbitrary connections between nodes to support
// mixing, splitting and gain adjustment. All functions use C
// linkage so they can be called from Dart via FFI.

#pragma once
#include <stdint.h>

#ifdef _WIN32
#  ifdef DART_VST_HOST_EXPORTS
#    define DVH_API __declspec(dllexport)
#  else
#    define DVH_API __declspec(dllimport)
#  endif
#else
#  define DVH_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles for the host, individual plug‑in wrappers and the
// graph itself. These pointers are managed internally by the native
// library. Clients must call the appropriate destroy functions to
// release memory.
typedef void* DVH_Host;
typedef void* DVH_Plugin;
typedef void* DVH_Graph;

// Simple transport information structure. This can be expanded in
// future versions to include more DAW state such as loop points,
// bar/beat positions, etc. All fields are in host (double or int)
// domain and should be filled out by the plug‑in before calling
// dvh_graph_set_transport().
typedef struct {
  double tempo;
  int32_t timeSigNum;
  int32_t timeSigDen;
  double ppqPosition;
  int32_t playing; // 0 = stopped, 1 = playing
} DVH_Transport;

// Create a new graph at the specified sample rate and maximum block
// size. The graph owns its own internal host used for VST loading
// (shared with other graphs). Returns a handle to the graph or
// nullptr on failure.
DVH_API DVH_Graph dvh_graph_create(double sample_rate, int32_t max_block);

// Destroy a graph created by dvh_graph_create(). After calling this
// the handle becomes invalid and must not be used again.
DVH_API void dvh_graph_destroy(DVH_Graph g);

// Remove all nodes and connections from the graph. Does not destroy
// the graph itself. Returns 1 on success.
DVH_API int32_t dvh_graph_clear(DVH_Graph g);

// Add a VST3 plug‑in to the graph. The module_path_utf8 must point
// to a .vst3 bundle on disk. class_uid_or_null is an optional
// UID string specifying which class within the module to instantiate;
// if null the first "Audio Module Class" is used. On success the
// new node’s ID is written to out_node_id and 1 is returned. On
// failure 0 is returned and out_node_id is untouched.
DVH_API int32_t dvh_graph_add_vst(DVH_Graph g,
                                  const char* module_path_utf8,
                                  const char* class_uid_or_null,
                                  int32_t* out_node_id);

// Add a mixer node with the given number of inputs. Each input
// represents a stereo bus. The mixer sums all connected inputs with
// per‑input gains (initially 0dB) and outputs a single stereo bus.
// Returns 1 on success and writes the new node ID to out_node_id.
DVH_API int32_t dvh_graph_add_mixer(DVH_Graph g, int32_t num_inputs, int32_t* out_node_id);

// Add a splitter node which simply forwards its input stereo bus to
// its output. Useful as an IO placeholder. Returns 1 on success.
DVH_API int32_t dvh_graph_add_split(DVH_Graph g, int32_t* out_node_id);

// Add a gain node with an initial gain in dB. The gain node exposes a
// single parameter (ID 0) representing a normalized gain value
// mapped from ‑60dB (0.0) to 0dB (1.0). Returns 1 on success.
DVH_API int32_t dvh_graph_add_gain(DVH_Graph g, float gain_db, int32_t* out_node_id);

// Connect the output of src_node to the input of dst_node. The bus
// indices are reserved for future multi‑bus support and must be zero
// for now. Returns 1 on success.
DVH_API int32_t dvh_graph_connect(DVH_Graph g,
                                  int32_t src_node, int32_t src_bus,
                                  int32_t dst_node, int32_t dst_bus);

// Disconnect the output of src_node from the input of dst_node. The
// bus indices must match a previous call to dvh_graph_connect().
// Returns 1 on success.
DVH_API int32_t dvh_graph_disconnect(DVH_Graph g,
                                     int32_t src_node, int32_t src_bus,
                                     int32_t dst_node, int32_t dst_bus);

// Specify which nodes act as the global input and output for the
// graph. If either is set to ‑1 it is ignored, allowing the graph to
// operate without a physical input or output. Returns 1 on success.
DVH_API int32_t dvh_graph_set_io_nodes(DVH_Graph g, int32_t input_node_or_minus1, int32_t output_node_or_minus1);

// Send a note on or off event to a specific node. If node_or_minus1
// is ‑1 the event is broadcast to all nodes. Returns 1 on success.
DVH_API int32_t dvh_graph_note_on(DVH_Graph g, int32_t node_or_minus1, int32_t ch, int32_t note, float vel);
DVH_API int32_t dvh_graph_note_off(DVH_Graph g, int32_t node_or_minus1, int32_t ch, int32_t note, float vel);

// Query the number of parameters available on a node. Returns zero if
// the node has no parameters or an invalid ID is supplied.
DVH_API int32_t dvh_graph_param_count(DVH_Graph g, int32_t node_id);

// Retrieve information about a parameter on a node. The title and
// units strings must have sufficient capacity as given by title_cap
// and units_cap. On success returns 1 and writes the parameter ID,
// title and units; on failure returns 0.
DVH_API int32_t dvh_graph_param_info(DVH_Graph g, int32_t node_id, int32_t index,
                                     int32_t* id_out,
                                     char* title_utf8, int32_t title_cap,
                                     char* units_utf8, int32_t units_cap);

// Get or set a parameter’s normalized value on a node. The normalized
// value is a float between 0.0 and 1.0. Returns the current value
// from dvh_graph_get_param() or 1/0 for dvh_graph_set_param().
DVH_API float   dvh_graph_get_param(DVH_Graph g, int32_t node_id, int32_t param_id);
DVH_API int32_t dvh_graph_set_param(DVH_Graph g, int32_t node_id, int32_t param_id, float normalized);

// Update the graph’s transport state. The native graph does not yet
// perform tempo‑synchronized processing but this information is
// preserved for future use. Returns 1 on success.
DVH_API int32_t dvh_graph_set_transport(DVH_Graph g, DVH_Transport t);

// Query the latency introduced by the graph in samples. At present
// latency compensation is not implemented and this always returns 0.
DVH_API int32_t dvh_graph_latency(DVH_Graph g);

// Process a block of audio through the graph. The input and output
// buffers must have at least num_frames samples. Returns 1 on
// success; on failure the contents of outL/outR are undefined.
DVH_API int32_t dvh_graph_process_stereo(DVH_Graph g,
                                         const float* inL, const float* inR,
                                         float* outL, float* outR,
                                         int32_t num_frames);

#ifdef __cplusplus
}
#endif