#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
binary="$(mktemp)"
trap 'rm -f "$binary"' EXIT
g++ -std=c++17 -Wall -Wextra -Werror -I "$root/native/include" "$root/test/native/view_logic_test.cpp" -o "$binary"
"$binary"
