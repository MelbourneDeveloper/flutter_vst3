#include "view_logic.h"
#include <cstdlib>
#include <iostream>
#include <vector>

void require(bool value) {
    if (!value) { std::cerr << "view logic assertion failed\n"; std::exit(1); }
}
void testOwnershipAndShm() {
    const int a = 1, b = 2;
    require(flutter_vst3::ownsEditor(&a, &a));
    require(!flutter_vst3::ownsEditor(&a, &b));
    require(!flutter_vst3::ownsEditor(nullptr, nullptr));
    require(flutter_vst3::localShmAddress(1234, 5, 5) == 1234);
    require(flutter_vst3::localShmAddress(1234, 5, 6) == 0);
    require(flutter_vst3::localShmAddress(0, 5, 5) == 0);
}
void testEditSuppression() {
    flutter_vst3::EditState edits;
    require(edits.shouldEcho(7));
    require(edits.begin(7));
    require(!edits.begin(7));
    require(!edits.shouldEcho(7));
    require(edits.shouldEcho(8));
    require(edits.end(7));
    require(!edits.end(7));
    require(edits.shouldEcho(7));
}
void testGestureSequence() {
    flutter_vst3::EditState edits;
    std::vector<char> events;
    if (edits.begin(1)) events.push_back('b');
    for (int tick = 0; tick < 10; ++tick) {
        require(!edits.shouldEcho(1));
        events.push_back('p');
    }
    if (edits.end(1)) events.push_back('e');
    require(events.size() == 12);
    require(events.front() == 'b' && events.back() == 'e');
    for (size_t i = 1; i + 1 < events.size(); ++i) require(events[i] == 'p');
}
void testStartupDecision() {
    require(flutter_vst3::kFlutterStartTimeoutMs == 10000);
    for (bool alive : {false, true}) for (bool failed : {false, true}) {
        require(!flutter_vst3::flutterStartFailed(alive, failed, false));
        require(flutter_vst3::flutterStartFailed(alive, failed, true) == (failed || !alive));
    }
}
int main() {
    flutter_vst3::EditState interrupted;
    require(interrupted.begin(7));
    require(interrupted.begin(2));
    require(interrupted.takeOpen() == std::set<uint32_t>({2, 7}));
    require(interrupted.takeOpen().empty());
    require(interrupted.shouldEcho(7));
    require(!interrupted.end(7));
    require(interrupted.begin(7));
    require(interrupted.end(7));
    testStartupDecision();
    testOwnershipAndShm();
    testEditSuppression();
    testGestureSequence();
    std::cout << "ownership, gesture state, edit suppression, shm routing and startup watchdog passed\n";
}
