#pragma once
#include <cstdint>
#include <atomic>
#include <set>

namespace flutter_vst3 {
/// Executes queued UI work only while its editor's liveness token is live.
template<class Work> inline void withLiveEditor(const std::atomic<bool>& alive, Work work) {
    if (alive.load()) work();
}
inline constexpr unsigned kFlutterStartTimeoutMs = 10000;
inline bool flutterStartFailed(bool uiAlive, bool engineFailed, bool hasOwner) {
    return hasOwner && (engineFailed || !uiAlive);
}
/// Pure ownership decisions shared by platform editors.
inline bool ownsEditor(const void* owner, const void* candidate) {
    return owner != nullptr && owner == candidate;
}
inline uintptr_t localShmAddress(int64_t address, int64_t sender, int64_t current) {
    return sender == current ? static_cast<uintptr_t>(address) : 0;
}
/// Tracks balanced gestures and suppresses host-to-view feedback while editing.
class EditState {
public:
    std::set<uint32_t> takeOpen() {
        std::set<uint32_t> result;
        result.swap(editing_);
        return result;
    }
    bool begin(uint32_t id) { return editing_.insert(id).second; }
    bool end(uint32_t id) { return editing_.erase(id) != 0; }
    bool shouldEcho(uint32_t id) const { return editing_.count(id) == 0; }
private:
    std::set<uint32_t> editing_;
};
/// Controller-owned address; never a process-global active instance.
struct ShmAddressSource {
    virtual ~ShmAddressSource() = default;
    virtual uintptr_t sharedMemoryAddress() const = 0;
    virtual void endOpenEdits() = 0;
    virtual bool isEditing(uint32_t id) const = 0;
};
}
