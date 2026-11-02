#!/usr/bin/env bash
# Builds and runs the native IPC round-trip tests on Linux and macOS.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="${VST3_IPC_TEST_BUILD_DIR:-$(mktemp -d)}"
mkdir -p "$build"

(cd "$root" && dart compile exe test/native/probe_worker.dart -o "$build/probe_worker")

libs=(-pthread)
if [ "$(uname)" = "Linux" ]; then libs+=(-lrt -ldl); fi

c++ -std=c++17 -O1 -g -Wall -Wextra -Werror \
  -I"$root/native/include" -I"$root/native/src" \
  "$root/native/src/vst3_ipc_host.cpp" \
  "$root/native/src/vst3_ipc_platform_posix.cpp" \
  "$root/test/native/ipc_host_test.cpp" \
  "$root/test/native/ipc_host_recovery_test.cpp" \
  "${libs[@]}" -o "$build/ipc_host_test"

"$build/ipc_host_test" "$build/probe_worker"

# Names are unlinked after the handshake, so a clean run or a failed start leaves none.
if [ "$(uname)" = "Linux" ]; then
  leaked="$(find /dev/shm -maxdepth 1 \( -name 'v3s*' -o -name 'sem.v3r*' -o -name 'sem.v3d*' \))"
  if [ -n "$leaked" ]; then
    printf 'FAIL leaked shared memory or semaphores:\n%s\n' "$leaked" >&2
    exit 1
  fi
  echo "PASS no shared memory or semaphores leaked"
fi
