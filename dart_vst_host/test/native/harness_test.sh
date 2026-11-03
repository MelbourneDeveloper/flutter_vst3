#!/usr/bin/env bash
# Failure injection for the root Makefile; no native/plugin build is needed.
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '#!/bin/sh\ncase "$PWD" in */"$FAIL_PACKAGE") exit 37;; esac\nexit 0\n' > "$tmp/dart"
cp "$tmp/dart" "$tmp/flutter"
chmod +x "$tmp/dart" "$tmp/flutter"
for package in dart_vst_host dart_vst_graph flutter_vst3 vsts/flutter_reverb vsts/echo; do
    if PATH="$tmp:$PATH" FAIL_PACKAGE="$package" make -C "$root" -o native -o dart-deps -o _test-native test > "$tmp/output" 2>&1; then
        printf 'FAIL: make test hid failure in %s\n' "$package" >&2
        exit 1
    fi
    grep -q 'Error 37' "$tmp/output"
    printf 'PASS: make test propagated %s exit 37\n' "$package"
done
