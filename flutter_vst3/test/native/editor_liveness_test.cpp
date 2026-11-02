#include "../../native/include/view_logic.h"
#include <atomic>
#include <cstdio>
int main() {
    std::atomic<bool> alive{false};
    int calls = 0;
    flutter_vst3::withLiveEditor(alive, [&] { ++calls; });
    if (calls != 0) { puts("FAIL H15 dead token ran work"); return 1; }
    alive.store(true);
    flutter_vst3::withLiveEditor(alive, [&] { calls += 7; });
    if (calls != 7) { puts("FAIL H15 live token skipped work"); return 1; }
    alive.store(false);
    flutter_vst3::withLiveEditor(alive, [&] { ++calls; });
    if (calls != 7) { puts("FAIL H15 expired token ran work"); return 1; }
    puts("PASS H15 dead/live/expired token exact work counts");
}
