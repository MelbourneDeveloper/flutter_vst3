#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
build="${VST3_E2E_BUILD_DIR:-/tmp/editor-e2e}"
: "${VST3_SDK_DIR:?Set VST3_SDK_DIR}"
cd "$root/vsts/echo"
flutter build linux --release
cmake -S . -B "$build/echo" -G Ninja -DCMAKE_BUILD_TYPE=Release -DSMTG_CREATE_PLUGIN_LINK=OFF -DFLUTTER_VST3_NATIVE_UI_ONLY=OFF
cmake --build "$build/echo" --target echo
cmake -S "$root/flutter_vst3/test/native" -B "$build/host" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$build/host" --target editor_host_test
bundle="$(find "$build/echo" -type d -name echo.vst3 -print -quit)"
test -n "$bundle"
mkdir -p "$build/missing" "$build/garbage"
rm -rf "$build/missing/echo.vst3" "$build/garbage/echo.vst3"
cp -a "$bundle" "$build/missing/"
cp -a "$bundle" "$build/garbage/"
rm "$build/missing/echo.vst3/Contents/x86_64-linux/lib/libapp.so"
printf 'not an ELF library\n' > "$build/garbage/echo.vst3/Contents/x86_64-linux/lib/libapp.so"
result=0
for mode in good missing garbage wire; do
    path="$bundle"
    if [[ "$mode" == missing || "$mode" == garbage ]]; then path="$build/$mode/echo.vst3"; fi
    xvfb-run -a "$build/host/editor_host_test" "$path" "$mode" | tee "$build/$mode.log" || result=1
    grep -q '^PASS ALL EDITOR CASES$' "$build/$mode.log" || result=1
done
cmake -S "$VST3_SDK_DIR" -B "$build/sdk" -G Ninja -DCMAKE_BUILD_TYPE=Release   -DSMTG_ADD_VSTGUI=OFF -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF -DSMTG_ADD_VST3_PLUGINS_SAMPLES=OFF -DSMTG_RUN_VST_VALIDATOR=OFF
cmake --build "$build/sdk" --target validator
xvfb-run -a "$(find "$build/sdk" -type f -name validator -print -quit)" "$bundle" || result=1
exit "$result"
