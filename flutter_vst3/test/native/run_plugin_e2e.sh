#!/usr/bin/env bash
# Builds the real Echo plugin, runs Steinberg's validator on it, and runs
# plugin_host_test against it. Usage: run_plugin_e2e.sh [build|test]; with no
# argument it does both. Building needs VST3_SDK_DIR, plus cl.exe on PATH on Windows.
set -euo pipefail

phase="${1:-all}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
build="${VST3_E2E_BUILD_DIR:-$(mktemp -d)}"
mkdir -p "$build"
build="$(cd "$build" && pwd)"
# On Windows CMake's default generator is Visual Studio, which the SDK's bundle layout needs.
case "$(uname)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) export CMAKE_GENERATOR="${CMAKE_GENERATOR:-Ninja}" ;;
esac

if [ "$phase" != test ]; then
: "${VST3_SDK_DIR:?Set VST3_SDK_DIR to the Steinberg VST3 SDK}"
export VST3_SDK_DIR
# Native sliders only: this checks audio and the VST3 contract, not the editor.
cmake -S "$root/vsts/echo" -B "$build/echo-native" -DCMAKE_BUILD_TYPE=Release \
  -DSMTG_CREATE_PLUGIN_LINK=OFF -DFLUTTER_VST3_NATIVE_UI_ONLY=ON
cmake --build "$build/echo-native" --config Release --target echo
cmake -S "$root/flutter_vst3/test/native" -B "$build/host" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build/host" --config Release --target plugin_host_test
cmake -S "$VST3_SDK_DIR" -B "$build/sdk" -DCMAKE_BUILD_TYPE=Release \
  -DSMTG_ADD_VSTGUI=OFF -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF -DSMTG_ADD_VST3_PLUGINS_SAMPLES=OFF -DSMTG_RUN_VST_VALIDATOR=OFF
cmake --build "$build/sdk" --config Release --target validator
# Reverb has no flutterEntrypoint, so it must build and validate with native sliders.
cmake -S "$root/vsts/flutter_reverb" -B "$build/reverb" -DCMAKE_BUILD_TYPE=Release -DSMTG_CREATE_PLUGIN_LINK=OFF -DFLUTTER_VST3_NATIVE_UI_ONLY=ON
cmake --build "$build/reverb" --config Release --target flutter_reverb
fi

if [ "$phase" = build ]; then exit 0; fi

bundle="$(find "$build/echo-native" -type d -name 'echo.vst3' | head -n 1)"
worker="$(find "$bundle/Contents" -type f \( -name echo_processor -o -name echo_processor.exe \) | head -n 1)"
test -x "$worker"

host_test="$(find "$build/host" -type f \( -name plugin_host_test -o -name plugin_host_test.exe \) | head -n 1)"
"$host_test" "$bundle" "$worker"

validator="$(find "$build/sdk" -type f \( -name validator -o -name validator.exe \) | head -n 1)"
"$validator" "$bundle"

"$validator" "$(find "$build/reverb" -type d -name 'flutter_reverb.vst3' | head -n 1)"

