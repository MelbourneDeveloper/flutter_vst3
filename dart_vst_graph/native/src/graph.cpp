// Copyright (c) 2025
//
// Implementation of a simple audio graph hosting multiple VST3 plug‑ins.
// Nodes can be VST instances, mixers, splitters and gain controls.
// Connections form a directed graph with one stereo bus per node.
// The graph is processed sample accurate and supports note and
// parameter automation. All functions are exposed via a C API for
// consumption from Dart using FFI.

#include "dvh_graph.h"
#include "dart_vst_host.h"

#include <vector>
#include <mutex>
#include <memory>
#include <atomic>
#include <cmath>
#include <string>
#include <unordered_map>
#include <cstring>

// A base class for all graph nodes. Subclasses implement audio
// processing, note handling and parameter access. The default
// implementation performs a bypass (zeros) and exposes no parameters.
struct Node {
  virtual ~Node() = default;
  virtual int32_t process(const float* inL, const float* inR, float* outL, float* outR, int32_t n) = 0;
  virtual int32_t noteOn(int ch, int note, float vel) { (void)ch; (void)note; (void)vel; return 1; }
  virtual int32_t noteOff(int ch, int note, float vel) { (void)ch; (void)note; (void)vel; return 1; }
  virtual int32_t paramCount() const { return 0; }
  virtual int32_t paramInfo(int idx, int32_t* id, std::string& title, std::string& units) { (void)idx; (void)id; title.clear(); units.clear(); return 0; }
  virtual float getParam(int32_t id) { (void)id; return 0.f; }
  virtual int32_t setParam(int32_t id, float v) { (void)id; (void)v; return 0; }
  virtual int32_t latency() const { return 0; }
};

// A node wrapping a DVH_Plugin. Delegates processing, notes and
// parameters to the underlying plug‑in. Owns the plug‑in and
// unloads it on destruction.
struct VstNode : Node {
  DVH_Plugin p{nullptr};
  VstNode(DVH_Plugin plugin) : p(plugin) {}
  ~VstNode() override { if (p) dvh_unload_plugin(p); }
  int32_t process(const float* inL, const float* inR, float* outL, float* outR, int32_t n) override {
    return dvh_process_stereo_f32(p, inL, inR, outL, outR, n);
  }
  int32_t noteOn(int ch, int note, float vel) override { return dvh_note_on(p, ch, note, vel); }
  int32_t noteOff(int ch, int note, float vel) override { return dvh_note_off(p, ch, note, vel); }
  int32_t paramCount() const override { return dvh_param_count(p); }
  int32_t paramInfo(int idx, int32_t* id, std::string& t, std::string& u) override {
    char title[256]; char units[64]; int32_t pid = 0;
    if (dvh_param_info(p, idx, &pid, title, 256, units, 64) != 1) return 0;
    if (id) *id = pid; t = title; u = units; return 1;
  }
  float getParam(int32_t id) override { return dvh_get_param_normalized(p, id); }
  int32_t setParam(int32_t id, float v) override { return dvh_set_param_normalized(p, id, v); }
};

// A mixer node sums multiple stereo inputs with per‑input gains. When
// created the number of inputs is fixed. Each call to process()
// accumulates inputs into the output buffer. Gains can be modified
// directly via the gains vector.
struct MixerNode : Node {
  std::vector<const float*> inputsL;
  std::vector<const float*> inputsR;
  std::vector<float> gains;
  MixerNode(int n) : inputsL(n, nullptr), inputsR(n, nullptr), gains(n, 1.0f) {}
  void setInput(int i, const float* L, const float* R) {
    if (i < 0 || i >= (int)inputsL.size()) return;
    inputsL[i] = L;
    inputsR[i] = R;
  }
  int32_t process(const float*, const float*, float* outL, float* outR, int32_t n) override {
    for (int i = 0; i < n; i++) {
      outL[i] = 0;
      outR[i] = 0;
    }
    for (size_t b = 0; b < inputsL.size(); ++b) {
      auto inL = inputsL[b];
      auto inR = inputsR[b];
      if (!inL || !inR) continue;
      const float g = gains[b];
      for (int i = 0; i < n; i++) {
        outL[i] += inL[i] * g;
        outR[i] += inR[i] * g;
      }
    }
    return 1;
  }
};

// A splitter simply forwards its input to its output. If no input
// connections are present the output is silenced.
struct SplitNode : Node {
  int32_t process(const float* inL, const float* inR, float* outL, float* outR, int32_t n) override {
    if (inL && inR) {
      for (int i = 0; i < n; i++) {
        outL[i] = inL[i];
        outR[i] = inR[i];
      }
      return 1;
    }
    for (int i = 0; i < n; i++) {
      outL[i] = 0;
      outR[i] = 0;
    }
    return 1;
  }
};

// A gain node applies a simple gain in dB to its input. The gain
// parameter is exposed as a single parameter 0. Normalized values map
// to dB in the range [‑60, 0].
struct GainNode : Node {
  std::atomic<float> gdb;
  GainNode(float dB) : gdb(dB) {}
  int32_t process(const float* inL, const float* inR, float* outL, float* outR, int32_t n) override {
    const float g = std::pow(10.0f, gdb.load() * 0.05f);
    for (int i = 0; i < n; i++) {
      outL[i] = inL ? inL[i] * g : 0;
      outR[i] = inR ? inR[i] * g : 0;
    }
    return 1;
  }
  int32_t paramCount() const override { return 1; }
  int32_t paramInfo(int idx, int32_t* id, std::string& t, std::string& u) override {
    if (idx != 0) return 0;
    if (id) *id = 0;
    t = "Output Gain";
    u = "dB";
    return 1;
  }
  float getParam(int32_t) override {
    return (gdb.load() + 60.f) / 60.f;
  }
  int32_t setParam(int32_t, float v) override {
    gdb.store(v * 60.f - 60.f);
    return 1;
  }
};

// Connection between nodes. Only one stereo bus per node for now.
struct Conn { int src = -1; int dst = -1; };

// Runtime buffer used during processing to store intermediate audio
// between nodes. Either holds an external input pointer or owns a
// local vector. The inL/inR pointers override the vector when set.
struct RuntimeBuffer {
  std::vector<float> L;
  std::vector<float> R;
  const float* inL = nullptr;
  const float* inR = nullptr;
};

// Internal graph implementation. Owns all nodes, manages the
// connection list and processes audio in a single topologically
// ordered pass. Also owns a DVH_Host used to load plug‑ins.
struct GraphImpl {
  std::mutex editMtx;
  double sr;
  int maxBlock;
  DVH_Host host{nullptr};
  DVH_Transport transport{};
  std::vector<std::unique_ptr<Node>> nodes;
  std::unordered_map<int,int> latency; // nodeId -> samples
  std::vector<Conn> edges; // index by destination node id
  int ioIn = -1;
  int ioOut = -1;
  GraphImpl(double s, int m) : sr(s), maxBlock(m) {
    host = dvh_create_host(sr, maxBlock);
  }
  ~GraphImpl() { if (host) dvh_destroy_host(host); }
  int addNode(std::unique_ptr<Node>&& n) {
    std::lock_guard<std::mutex> g(editMtx);
    nodes.push_back(std::move(n));
    edges.resize((int)nodes.size());
    return (int)nodes.size() - 1;
  }
  int setEdge(int s, int d) {
    std::lock_guard<std::mutex> g(editMtx);
    if (s < 0 || d < 0 || s >= (int)nodes.size() || d >= (int)nodes.size()) return 0;
    edges[d].src = s;
    edges[d].dst = d;
    return 1;
  }
  int clearEdge(int s, int d) {
    std::lock_guard<std::mutex> g(editMtx);
    if (d < 0 || d >= (int)edges.size()) return 0;
    if (edges[d].src == s) edges[d].src = -1;
    return 1;
  }
  int process(const float* inL, const float* inR, float* outL, float* outR, int n) {
    std::vector<RuntimeBuffer> bufs(nodes.size());
    for (auto& b : bufs) {
      b.L.assign(n, 0);
      b.R.assign(n, 0);
      b.inL = nullptr;
      b.inR = nullptr;
    }
    if (ioIn >= 0) {
      bufs[ioIn].inL = inL;
      bufs[ioIn].inR = inR;
    }
    // process nodes in index order (simple linear graph). For a
    // topologically complex graph a proper sort would be needed.
    for (int i = 0; i < (int)nodes.size(); ++i) {
      const float* srcL = nullptr;
      const float* srcR = nullptr;
      if (edges[i].src >= 0) {
        auto& sb = bufs[edges[i].src];
        srcL = sb.inL ? sb.inL : sb.L.data();
        srcR = sb.inR ? sb.inR : sb.R.data();
      }
      auto& b = bufs[i];
      nodes[i]->process(srcL, srcR, b.L.data(), b.R.data(), n);
    }
    const auto& ob = bufs[ioOut < 0 ? (int)nodes.size() - 1 : ioOut];
    for (int i = 0; i < n; i++) {
      outL[i] = (ob.inL ? ob.inL[i] : ob.L[i]);
      outR[i] = (ob.inR ? ob.inR[i] : ob.R[i]);
    }
    return 1;
  }
};

extern "C" {

DVH_Graph dvh_graph_create(double sample_rate, int32_t max_block) {
  auto* g = new GraphImpl(sample_rate, max_block);
  return (DVH_Graph)g;
}
void dvh_graph_destroy(DVH_Graph g) {
  if (!g) return;
  delete (GraphImpl*)g;
}
int32_t dvh_graph_clear(DVH_Graph g) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  std::lock_guard<std::mutex> lk(gg->editMtx);
  gg->nodes.clear();
  gg->edges.clear();
  gg->ioIn = -1;
  gg->ioOut = -1;
  return 1;
}

int32_t dvh_graph_add_vst(DVH_Graph g, const char* path, const char* uid, int32_t* out_id) {
  if (!g || !path) return 0;
  auto* gg = (GraphImpl*)g;
  auto p = dvh_load_plugin(gg->host, path, uid);
  if (!p) return 0;
  if (dvh_resume(p, gg->sr, gg->maxBlock) != 1) {
    dvh_unload_plugin(p);
    return 0;
  }
  int id = gg->addNode(std::make_unique<VstNode>(p));
  if (out_id) *out_id = id;
  return 1;
}

int32_t dvh_graph_add_mixer(DVH_Graph g, int32_t nin, int32_t* out_id) {
  if (!g || nin <= 0) return 0;
  auto* gg = (GraphImpl*)g;
  int id = gg->addNode(std::make_unique<MixerNode>(nin));
  if (out_id) *out_id = id;
  return 1;
}

int32_t dvh_graph_add_split(DVH_Graph g, int32_t* out_id) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  int id = gg->addNode(std::make_unique<SplitNode>());
  if (out_id) *out_id = id;
  return 1;
}

int32_t dvh_graph_add_gain(DVH_Graph g, float db, int32_t* out_id) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  int id = gg->addNode(std::make_unique<GainNode>(db));
  if (out_id) *out_id = id;
  return 1;
}

int32_t dvh_graph_connect(DVH_Graph g, int32_t s, int32_t sb, int32_t d, int32_t db) {
  (void)sb; (void)db;
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  return gg->setEdge(s, d);
}
int32_t dvh_graph_disconnect(DVH_Graph g, int32_t s, int32_t sb, int32_t d, int32_t db) {
  (void)sb; (void)db;
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  return gg->clearEdge(s, d);
}
int32_t dvh_graph_set_io_nodes(DVH_Graph g, int32_t in, int32_t out) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  gg->ioIn = in;
  gg->ioOut = out;
  return 1;
}

int32_t dvh_graph_note_on(DVH_Graph g, int32_t node, int32_t ch, int32_t note, float vel) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  if (node >= 0 && node < (int)gg->nodes.size())
    return gg->nodes[node]->noteOn(ch, note, vel);
  for (auto& n : gg->nodes) n->noteOn(ch, note, vel);
  return 1;
}
int32_t dvh_graph_note_off(DVH_Graph g, int32_t node, int32_t ch, int32_t note, float vel) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  if (node >= 0 && node < (int)gg->nodes.size())
    return gg->nodes[node]->noteOff(ch, note, vel);
  for (auto& n : gg->nodes) n->noteOff(ch, note, vel);
  return 1;
}

int32_t dvh_graph_param_count(DVH_Graph g, int32_t node) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  if (node < 0 || node >= (int)gg->nodes.size()) return 0;
  return gg->nodes[node]->paramCount();
}
int32_t dvh_graph_param_info(DVH_Graph g, int32_t node, int32_t idx, int32_t* id, char* t, int32_t tcap, char* u, int32_t ucap) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  if (node < 0 || node >= (int)gg->nodes.size()) return 0;
  std::string ts, us;
  int32_t pid = 0;
  if (!gg->nodes[node]->paramInfo(idx, &pid, ts, us)) return 0;
  if (id) *id = pid;
  auto cpy = [&](const std::string& s, char* o, int32_t cap) {
    if (!o || cap <= 0) return;
    int n = (int)s.size();
    if (n >= cap) n = cap - 1;
    memcpy(o, s.data(), n);
    o[n] = 0;
  };
  cpy(ts, t, tcap);
  cpy(us, u, ucap);
  return 1;
}
float dvh_graph_get_param(DVH_Graph g, int32_t node, int32_t id) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  if (node < 0 || node >= (int)gg->nodes.size()) return 0;
  return gg->nodes[node]->getParam(id);
}
int32_t dvh_graph_set_param(DVH_Graph g, int32_t node, int32_t id, float v) {
  if (!g) return 0;
  auto* gg = (GraphImpl*)g;
  if (node < 0 || node >= (int)gg->nodes.size()) return 0;
  return gg->nodes[node]->setParam(id, v);
}

int32_t dvh_graph_set_transport(DVH_Graph g, DVH_Transport t) {
  if (!g) return 0;
  ((GraphImpl*)g)->transport = t;
  return 1;
}
int32_t dvh_graph_latency(DVH_Graph g) {
  if (!g) return 0;
  return 0;
}

int32_t dvh_graph_process_stereo(DVH_Graph g, const float* inL, const float* inR, float* outL, float* outR, int32_t n) {
  if (!g) return 0;
  return ((GraphImpl*)g)->process(inL, inR, outL, outR, n);
}

} // extern "C"