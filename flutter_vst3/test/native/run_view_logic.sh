#!/usr/bin/env bash
# Usage: run_view_logic.sh [build|test]. With no argument it does both.
set -euo pipefail
phase="${1:-all}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="${VST3_E2E_BUILD_DIR:-$(mktemp -d)}"
mkdir -p "$build"
binary="$build/view_logic_test"
if [ "$phase" != test ]; then
  g++ -std=c++17 -Wall -Wextra -Werror -I "$root/native/include" "$root/test/native/view_logic_test.cpp" -o "$binary"
fi
if [ "$phase" != build ]; then "$binary"; fi
